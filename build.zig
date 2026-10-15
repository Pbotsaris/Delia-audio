const std = @import("std");

/// ALSA is vendored as a git submodule and linked statically.
/// On first build, `configure && make` run inside `vendor/alsa` to produce `libasound.a`.
const Alsa = struct {
    const src_dir = "vendor/alsa";
    const lib_path = "src/.libs/libasound.a";
    const include_dir = "include";

    fn install(b: *std.Build) void {
        const project_root = b.build_root.path.?;
        const rel_lib_path = b.pathJoin(&.{ src_dir, lib_path });

        b.build_root.handle.access(b.graph.io, rel_lib_path, .{}) catch {
            const build_alsa = b.step("build-alsa", "Build the vendored ALSA library");

            const config_cmd = b.addSystemCommand(&.{
                b.pathJoin(&.{ project_root, src_dir, "configure" }),
                "--enable-shared=no",
                "--enable-static=yes",
                "--prefix",
                b.pathJoin(&.{ project_root, src_dir }),
            });

            build_alsa.dependOn(&config_cmd.step);

            const make_cmd = b.addSystemCommand(&.{ "make", "-C", b.pathJoin(&.{ project_root, src_dir }) });
            build_alsa.dependOn(&make_cmd.step);

            b.getInstallStep().dependOn(&make_cmd.step);
        };
    }

    fn link(b: *std.Build, mod: *std.Build.Module) void {
        mod.addIncludePath(b.path(b.pathJoin(&.{ src_dir, include_dir })));
        mod.addObjectFile(b.path(b.pathJoin(&.{ src_dir, lib_path })));
        mod.link_libc = true;

        // NOTE TO SELF:
        // Statically linked, alsa-lib locates its plugin dir (`default` -> pipewire, pulse, ...)
        // with `dlinfo(RTLD_DI_ORIGIN)` on the object that contains it, which is now our executable. 
        // glibc only computes the main executable's origin when it has to expand `$ORIGIN` in its rpath; 
        // otherwise `dlinfo` dereferences NULL (glibc 2.44). The rpath entry itself is harmless: nothing is dlopened from next to the binary.
        mod.addRPathSpecial("$ORIGIN");
    }
};

/// Platform audio backends. Each one is a module `core/backends/<name>` rooted at
/// `src/core/backends/<name>/root.zig`, built only on the targets it supports, and exposed to
/// the source as `@import("build_options").<name>` so code can skip what was not built.
const Backend = enum {
    alsa,

    fn supports(backend: Backend, os: std.Target.Os.Tag) bool {
        return switch (backend) {
            .alsa => os == .linux,
        };
    }

    /// Vendored builds, system libraries and frameworks: whatever the module needs to link.
    fn link(backend: Backend, b: *std.Build, mod: *std.Build.Module) void {
        switch (backend) {
            .alsa => {
                Alsa.install(b);
                Alsa.link(b, mod);
            },
        }
    }
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    ////////////////////////// MODULES ///////////////////////////////////////////
    // One named module per subsystem so files import `@import("core/buffer")` rather than
    // `@import("../buffer/root.zig")`. A file belongs to exactly one module and a module
    // may only import files below its root, so the imports below are the real dependency
    // graph: a cycle or a missing edge fails at compile time.
    //
    // `core/` and `core/backends/` are folders, not modules: a `core` module rooted at
    // `src/core/root.zig` would contain the files of `core/buffer`, and a file may not
    // belong to two modules. The slash is only part of the name.
    //
    // The test runner only collects `test` blocks from the files of the module it was
    // given, so every module is also its own test root (see TESTS below).

    const Named = struct { name: []const u8, mod: *std.Build.Module };

    const buffer = b.createModule(.{
        .root_source_file = b.path("src/core/buffer/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const utils = b.createModule(.{
        .root_source_file = b.path("src/utils/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const common = b.createModule(.{
        .root_source_file = b.path("src/core/common/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dsp = b.createModule(.{
        .root_source_file = b.path("src/dsp/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    dsp.addImport("core/common", common);

    const graph = b.createModule(.{
        .root_source_file = b.path("src/core/graph/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    graph.addImport("core/buffer", buffer);
    graph.addImport("core/common", common);

    // One root module shared by the executable, the compile-only check, and the tests.
    const root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // An ArrayList, not an array: which backends are built depends on the target, which is
    // only known at runtime here.
    var modules: std.ArrayList(Named) = .empty;
    modules.appendSlice(b.allocator, &.{
        .{ .name = "core/buffer", .mod = buffer },
        .{ .name = "core/common", .mod = common },
        .{ .name = "core/graph", .mod = graph },
        .{ .name = "utils", .mod = utils },
        .{ .name = "dsp", .mod = dsp },
    }) catch @panic("OOM");

    ////////////////////////// BACKENDS //////////////////////////////////////////
    // `build_options.<name>` is true when the backend's module was built for this target.

    const build_options = b.addOptions();

    for (std.enums.values(Backend)) |backend| {
        const name = @tagName(backend);
        const enabled = backend.supports(target.result.os.tag);

        build_options.addOption(bool, name, enabled);
        if (!enabled) continue;

        const mod = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/core/backends/{s}/root.zig", .{name})),
            .target = target,
            .optimize = optimize,
        });
        mod.addImport("core/buffer", buffer);
        mod.addImport("core/common", common);
        mod.addImport("dsp", dsp);
        backend.link(b, mod);

        modules.append(b.allocator, .{ .name = b.fmt("core/backends/{s}", .{name}), .mod = mod }) catch @panic("OOM");
    }

    for (modules.items) |m| root.addImport(m.name, m.mod);
    root.addOptions("build_options", build_options);

    ////////////////////////// BUILD / RUN ///////////////////////////////////////
    const exe = b.addExecutable(.{
        .name = "delia",
        .root_module = root,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    ////////////////////////// CHECK (zls build-on-save) /////////////////////////
    // Analysis is lazy: the exe alone only checks what `main` reaches. The test binaries
    // (compiled, not run, in TESTS below) cover every module's tests and what they call.

    const exe_check = b.addExecutable(.{
        .name = "delia_check",
        .root_module = root,
    });

    const check = b.step("check", "Check if the app and all tests compile");
    check.dependOn(&exe_check.step);

    ////////////////////////// Examples /////////////////////////
    // run the module examples and `src/examples.zig`  with `zig build example -- module <name> [args...]`
    // where `src/example.zig` module is called 'root'.
    // ex: zig build example -- alsa playback-sine hw:0 5

    const example_mod = b.createModule(.{
        .root_source_file = b.path("src/examples_main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const example_exe = b.addExecutable(.{
        .name = "delia_example",
        .root_module = example_mod,
    });

    for (modules.items) |mod| example_mod.addImport(mod.name, mod.mod);
    example_mod.addOptions("build_options", build_options);

    check.dependOn(&example_exe.step);

    const example_run_cmd = b.addRunArtifact(example_exe);
    if (b.args) |args| example_run_cmd.addArgs(args);

    const examples_step = b.step("example", "Run module example: zig build example -- module <name> [args...]");
    examples_step.dependOn(&example_run_cmd.step);

    ////////////////////////// TESTS /////////////////////////////////////////////

    const test_filters = b.option(
        []const []const u8,
        "test-filter",
        "Only run tests whose name contains this string (repeatable)",
    ) orelse &.{};

    const test_step = b.step("test", "Run unit tests");

    // One test binary per module, root included; the runner would otherwise only see
    // tests in main.zig's own files.
    // Appended after EXAMPLES so the examples exe does not import `root`.
    modules.append(b.allocator, .{ .name = "root", .mod = root }) catch @panic("OOM");

    for (modules.items) |m| {
        const file_name = std.mem.replaceOwned(u8, b.allocator, m.name, "/", "_") catch @panic("OOM");
        const unit_tests = b.addTest(.{
            .name = b.fmt("test_{s}", .{file_name}),
            .root_module = m.mod,
            .filters = test_filters,
        });

        check.dependOn(&unit_tests.step);
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    }

    ////////////////////////// BENCHMARKS ////////////////////////////////////////

    const bench_mod = b.createModule(.{
        .root_source_file = b.path("src/benchmarks.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zbench = b.dependency("zbench", .{ .target = target, .optimize = optimize });
    bench_mod.addImport("zbench", zbench.module("zbench"));
    bench_mod.addImport("dsp", dsp);

    const exe_bench = b.addExecutable(.{
        .name = "delia_bench",
        .root_module = bench_mod,
    });

    const bench_run_cmd = b.addRunArtifact(exe_bench);
    const bench_step = b.step("bench", "Run the benchmarks");
    bench_step.dependOn(&bench_run_cmd.step);
}
