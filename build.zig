const std = @import("std");

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
    exe.linkLibC();
    exe.linkSystemLibrary("asound");

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

    exe_check.linkLibC();
    exe_check.linkSystemLibrary("asound");
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

    exe_unit_tests.linkLibC();
    exe_unit_tests.linkSystemLibrary("asound");

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
