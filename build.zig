const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Note building a static library ()
    //    const lib = b.addStaticLibrary(.{
    //        .name = "audio_engine_proto",
    //        .root_source_file = b.path("src/root.zig"),
    //        .optimize = optimize,
    //        .target = target,
    //    });
    //
    //   b.installArtifact(lib);
    const exe = b.addExecutable(.{
        .name = "audio_engine_proto",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.linkSystemLibrary("asound");
    exe.addIncludePath(b.path("src/c"));

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

    /////// CHECKS

    const exe_check = b.addExecutable(.{
        .name = "audio_engine_proto_check",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.linkLibC();
    exe_check.linkSystemLibrary("asound");
    exe_check.addIncludePath(b.path("src/c"));

    b.installArtifact(exe_check);

    const check = b.step("check", "Check if the app compile");
    check.dependOn(&exe_check.step);

    /////// TESTS

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

    // const exe_alsa_unit_tests = b.addTest(.{
    //     .root_source_file = b.path("src/alsa/settings.zig"),
    //     .target = target,
    //     .optimize = optimize,
    // });

    exe_unit_tests.linkLibC();
    exe_unit_tests.linkSystemLibrary("asound");
    //  mocking alsa for the unit tests
    //exe_unit_tests.defineCMacro("USE_MOCK_ALSA", "1");
    exe_unit_tests.addIncludePath(b.path("src/c"));

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
