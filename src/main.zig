const std = @import("std");

const haversine = @import("haversine.zig").haversine;

const earth_radius = 6372.8;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    const alloc = gpa.allocator();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    if (args.len != 3) {
        std.debug.print("Usage: {s} [rng seed] [number of pairs to generate]", .{args[0]});
        return error.InvalidArgument;
    }

    const seed = try std.fmt.parseInt(u64, args[1], 0);
    const pair_count = try std.fmt.parseInt(u64, args[2], 0);
    var rng = std.Random.DefaultPrng.init(seed);

    const out_file_name = try std.fmt.allocPrintZ(alloc, "haversine_pairs_{d}.json", .{pair_count});
    defer alloc.free(out_file_name);
    const out_file = try std.fs.cwd().createFile(
        out_file_name,
        .{ .read = false, .truncate = true },
    );
    defer out_file.close();

    const distances_file_name = try std.fmt.allocPrintZ(alloc, "haversine_pairs_{d}", .{pair_count});
    defer alloc.free(distances_file_name);
    const distances_file = try std.fs.cwd().createFile(
        distances_file_name,
        .{ .read = false, .truncate = true },
    );
    defer distances_file.close();

    const sum = try generate(out_file.writer().any(), distances_file.writer().any(), rng.random(), pair_count);

    const stdout = std.io.getStdOut().writer();
    try stdout.print("RNG seed:     {d}\n", .{seed});
    try stdout.print("Pair count:   {d}\n", .{pair_count});
    try stdout.print("Expected sum: {d}\n", .{sum});
}

fn generate(out_pairs_writer: std.io.AnyWriter, out_distances_writer: std.io.AnyWriter, rand: std.Random, num_pairs: u64) !f64 {
    var json_bw = std.io.bufferedWriter(out_pairs_writer);
    const json = json_bw.writer();

    var answers_bw = std.io.bufferedWriter(out_distances_writer);
    const answers = answers_bw.writer();

    _ = try json.write("{\"pairs\": [\n");
    defer _ = json.write("]}\n") catch {};

    var sum: f64 = 0;
    const sum_coef = 1.0 / @as(f64, @floatFromInt(num_pairs));

    const pairs_per_cluster = 1024;
    var cluster = randomCluster(rand);
    for (0..num_pairs) |i| {
        if (@mod(i, pairs_per_cluster) == 0) {
            cluster = randomCluster(rand);
        }
        const x0 = rand.float(f64) * (cluster.x_max - cluster.x_min) + cluster.x_min;
        const y0 = rand.float(f64) * (cluster.y_max - cluster.y_min) + cluster.y_min;
        const x1 = rand.float(f64) * (cluster.x_max - cluster.x_min) + cluster.x_min;
        const y1 = rand.float(f64) * (cluster.y_max - cluster.y_min) + cluster.y_min;
        const haversine_distance = haversine(x0, y0, x1, y1, earth_radius);

        sum += sum_coef * haversine_distance;

        const separator = if (i == (num_pairs - 1)) "\n" else ",\n";
        try json.print("    {{\"x0\":{d:.16}, \"y0\":{d:.16}, \"x1\":{d:.16}, \"y1\":{d:.16}}}{s}", .{ x0, y0, x1, y1, separator });
        try answers.writeAll(std.mem.asBytes(&haversine_distance));
    }
    try answers.writeAll(std.mem.asBytes(&sum));

    try json_bw.flush();
    try answers_bw.flush();

    return sum;
}

const Cluster = struct {
    x_min: f64,
    x_max: f64,
    y_min: f64,
    y_max: f64,
};

fn randomCluster(rand: std.Random) Cluster {
    const cluster_size = 32;
    const x_center = rand.float(f64) * 360 - 180; // longitude -180 - 180
    const y_center = rand.float(f64) * 180 - 90; // latitude -90 - 90

    return Cluster{
        .x_min = @max(x_center - cluster_size, -180),
        .x_max = @min(x_center + cluster_size, 180),
        .y_min = @max(y_center - cluster_size, -90),
        .y_max = @min(y_center + cluster_size, 90),
    };
}
