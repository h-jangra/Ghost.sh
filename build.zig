const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "ghost",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (comptime @hasField(std.Build, "args")) {
        if (b.args) |args| run_cmd.addArgs(args);
    } else {
        run_cmd.addPassthruArgs();
    }
    b.step("run", "Run the app").dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit tests");
    const test_files = [_][]const u8{
        "src/main.zig",
        "src/completion.zig",
        "src/editor.zig",
        "src/render.zig",
        "src/history_expansion.zig",
    };
    for (test_files) |file| {
        const unit_test = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(file),
                .target = target,
                .optimize = optimize,
            }),
        });
        test_step.dependOn(&b.addRunArtifact(unit_test).step);
    }
}
