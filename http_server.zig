const std = @import("std");

fn handleConnection(conn: std.net.Server.Connection) !void {
    // Define connection reader and writer buffers.
    // Similar to stdout & stdin writers and readers, we use buffers for performance
    // considerations for networking streams as well.
    var conn_reader_buf: [1024]u8 = undefined;
    var conn_writer_buf: [1024]u8 = undefined;
    var conn_reader = conn.stream.reader(&conn_reader_buf);
    var conn_writer = conn.stream.writer(&conn_writer_buf);

    // std.http.Server can technically wrap any type of reader and writer.
    // We supply a TCP connection.
    // Initiliaze a HTTP server with passing defined reader and writer respectively.
    // Inputs require generic reader and writer interface as we did previously with other
    // type of readers and writers.
    // The returned server is ready for receiveHead to be called.
    var http_server = std.http.Server.init(
        conn_reader.interface(),
        &conn_writer.interface,
    );

    // Parsing the request once read.
    var request = try http_server.receiveHead();
    // As we try to process data or sending new data to the server;
    // request must be a POST request, if not then it is an error!
    if (request.head.method != .POST) {
        request.respond("", .{ .status = .bad_request }) catch {};
        return error.BadRequest;
    }

    // Any error being happened after this point is a server's fault, not the client's.
    // errdefer is a special kind of defer, which executes only when an error is returned.
    // An important caveat is that you cannot return an error within an errdefer, so if
    // our response fails, we will not fallback on anything else. This behavior is sensible
    // for our case, though.
    errdefer request.respond("", .{
        .status = .internal_server_error,
    }) catch {};

    // Create a reader to handle the request. This function also handles the HTTP expect: 100
    var reader_buf: [1024]u8 = undefined;
    const reader = try request.readerExpectContinue(&reader_buf);

    // Reading the request --- It's just a reader!
    const text = try reader.takeDelimiterExclusive(0);

    // To send our response, we build it with a std.http.BodyWriter.
    var body_writer_buf: [1024]u8 = undefined;
    var body_writer = try request.respondStreaming(&body_writer_buf, .{});
    const body = &body_writer.writer;

    try body.print("You said: {s}\n", .{text});
    try body.flush();
    // std.http.BodyWriter needs to do some extra stuff to finish and actually send the body,
    // so we have to explicitly call end.
    try body_writer.end();
}

pub fn main() !void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8000);
    var tcp_server = try addr.listen(.{ .reuse_address = true });

    serve: while (true) {
        const conn = tcp_server.accept() catch |e| {
            std.log.err("accept: {}", .{e});
            continue :serve;
        };
        defer conn.stream.close();

        // By putting all of that behaviour in a function, we can simplify our error handling-
        // code significantly.
        handleConnection(conn) catch |e| {
            std.log.err("handleConnection: {}", .{e});
        };
    }
}
