const std = @import("std");

const AudioBackend = enum {
    alsa,
    jack,
};

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

// build and statically link the alsa library
const alsa = Deps{
    .name = "Alsa",
    .src_dir = "vendor/alsa",
    .lib_path = "src/.libs/libasound.a",
    .include_dir = "include",
};

fn pathExists(p: []const u8) bool {
    std.fs.cwd().access(p, .{}) catch {
        return false;
    };

    return true;
}

fn detectLinuxAudioBackend() AudioBackend {
    const jack_paths = &[_][]const u8{
        "/usr/lib/libjack.so",
        "/usr/local/lib/libjack.so",
        "/usr/lib64/libjack.so",
    };

    for (jack_paths) |path| {
        if (pathExists(path)) {
            std.log.info("JACK library found at: {s}", .{path});
            return .jack;
        }
    }

    std.log.info("JACK library not found. Falling back to ALSA.", .{});
    return .alsa;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Audio backend selection
    const backend = detectLinuxAudioBackend();

    const options = b.addOptions();
    options.addOption(AudioBackend, "audio_backend", backend);

    ////////////////////////// BUILD //////////////////////////////////////////////
    const exe = b.addExecutable(.{
        .name = "audio_engine_proto",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // ALSA: in vendor/alsa
    alsa.install(b);

    const alsa_include_path = alsa.joinIncludePath(b);
    const alsa_lib_path = alsa.joinLibPath(b);

    exe.addIncludePath(alsa_include_path);
    exe.addObjectFile(alsa_lib_path);

    // JACK2: headers in vendor/jack2
    // Libary must be dynamically linked as library is shared by both server and clients
    // If system does not have jack2 installed, we fall back to pulse audio then ALSA

    // Add the path to the JACK headers from the submodule
    if (backend == .jack) {
        exe.addIncludePath(b.path("vendor/jack"));
        // Dynamically link to the JACK shared library
        exe.linkSystemLibrary("jack");
    }

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

    exe.root_module.addOptions("audio_backend", options);

    ////////////////////////// CHECK //////////////////////////////////////////////

    const exe_check = b.addExecutable(.{
        .name = "audio_engine_proto_check",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.root_module.addOptions("audio_backend", options);

    exe_check.addIncludePath(alsa_include_path);
    exe_check.addObjectFile(alsa_lib_path);
    exe_check.linkLibC();

    if (backend == .jack) {
        exe_check.addIncludePath(b.path("vendor/jack"));
        exe_check.linkSystemLibrary("jack");
    }

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

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_unit_tests.root_module.addOptions("audio_backend", options);

    exe_unit_tests.addIncludePath(alsa_include_path);
    exe_unit_tests.addObjectFile(alsa_lib_path);
    exe_unit_tests.linkLibC();

    if (backend == .jack) {
        exe_unit_tests.addIncludePath(b.path("vendor/jack"));
        exe_unit_tests.linkSystemLibrary("jack");
    }

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
