const std = @import("std");

const Deps = struct {
    const Self = @This();

    name: []const u8,
    src_dir: []const u8,
    lib_path: []const u8,
    include_dir: []const u8,

    fn install(comptime self: Self, b: *std.Build) void {
        const project_root = b.build_root.path.?;
        const lib_path = b.pathJoin(&.{ project_root, self.src_dir, self.lib_path });

        std.fs.accessAbsolute(lib_path, .{}) catch {
            const build_alsa = b.step("build-" ++ self.name, "Build" ++ self.name ++ "Library");

            const config_cmd = b.addSystemCommand(&.{
                b.pathJoin(&.{ project_root, self.src_dir, "configure" }),
                "--enable-shared=no",
                "--enable-static=yes",
                "--prefix",
                b.pathJoin(&.{ project_root, self.src_dir }),
            });

            build_alsa.dependOn(&config_cmd.step);

            const make_cmd = b.addSystemCommand(&.{
                "make",
                "-C",
                b.pathJoin(&.{ project_root, self.src_dir }),
            });

            build_alsa.dependOn(&make_cmd.step);

            b.getInstallStep().dependOn(&make_cmd.step);
        };
    }

    fn joinIncludePath(self: Self, b: *std.Build) std.Build.LazyPath {
        const path = b.pathJoin(&.{ self.src_dir, self.include_dir });
        return b.path(path);
    }
    fn joinLibPath(self: Self, b: *std.Build) std.Build.LazyPath {
        const path = b.pathJoin(&.{ self.src_dir, self.lib_path });
        return b.path(path);
    }
};

const alsa = Deps{
    .name = "Alsa",
    .src_dir = "vendor/alsa",
    .lib_path = "src/.libs/libasound.a",
    .include_dir = "include",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    ////////////////////////// BUILD //////////////////////////////////////////////
    const exe = b.addExecutable(.{
        .name = "audio_engine_proto",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // alsa
    alsa.install(b);

    const alsa_include_path = alsa.joinIncludePath(b);
    const alsa_lib_path = alsa.joinLibPath(b);

    exe.addIncludePath(alsa_include_path);
    exe.addObjectFile(alsa_lib_path);

    exe.linkLibC();
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    // Allow args: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    //  create the run step
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    ////////////////////////// CHECK //////////////////////////////////////////////

    const exe_check = b.addExecutable(.{
        .name = "audio_engine_proto_check",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.addIncludePath(alsa_include_path);
    exe_check.addObjectFile(alsa_lib_path);
    exe_check.linkLibC();

    const check = b.step("check", "Check if the app compile");
    check.dependOn(&exe_check.step);

    ////////////////////////// BENCHMARKS ////////////////////////////////////////////

    const exe_bench = b.addExecutable(.{
        .name = "audio_engine_proto_bench",
        .root_source_file = b.path("src/benchmarks.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zbench_ops = .{ .target = target, .optimize = optimize };
    const zbench_module = b.dependency("zbench", zbench_ops).module("zbench");

    exe_bench.root_module.addImport("zbench", zbench_module);

    const bench_run_cmd = b.addRunArtifact(exe_bench);
    const benchmark = b.step("bench", "Run the benchmarks");

    benchmark.dependOn(&bench_run_cmd.step);

    //////////////// TESTS////////////////////////////////////////////////

    // step for running unit tests
    //   const lib_unit_tests = b.addTest(.{
    //       .root_source_file = b.path("src/root.zig"),
    //       .target = target,
    //       .optimize = optimize,
    //   });

    //   const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.addIncludePath(alsa_include_path);
    exe_unit_tests.addObjectFile(alsa_lib_path);
    exe_unit_tests.linkLibC();

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
