const std = @import("std");

pub fn main() !void {
    const addr = std.net.Address.initIp4(
        .{ 127, 0, 0, 1 },
        8000,
    );

    var tcp_server = try addr.listen(.{
        .reuse_address = true,
    });

    serve: while (true) {
        const conn = tcp_server.accept() catch |e| {
            std.log.err("accept: {}", .{e});
            continue :serve;
        };
        defer conn.stream.close();

        while (true) {
            var reader_buf: [1024]u8 = undefined;
            var stream_reader = conn.stream.reader(&reader_buf);
            const reader = stream_reader.interface();

            const msg = reader.takeDelimiterExclusive('\n') catch |e| {
                std.log.err("read: {}", .{e});
                continue :serve;
            };

            var writer_buf: [1024]u8 = undefined;
            var stream_writer = conn.stream.writer(&writer_buf);
            const writer = &stream_writer.interface;

            writer.print("you said: {s}\n", .{msg}) catch |e| {
                std.log.err("write: {}", .{e});
                continue :serve;
            };
            writer.flush() catch |e| {
                std.log.err("flush: {}", .{e});
                continue :serve;
            };
        }
    }
}
