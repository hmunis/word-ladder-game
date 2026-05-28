const std = @import("std");

// Input: word dictionary
// Output: total number of words found in dictionary
// Counts the words seperated by newlines in the dictionary.
fn countWordlist(text: []const u8) usize {
    var count: usize = 0;
    var word_iter = std.mem.tokenizeScalar(u8, text, '\n');
    while (word_iter.next()) |_| {
        count += 1;
    }

    return count;
}

// Input: word dictionary
// Output: array of 4-character strings
// Parse the dictionary and store each word string from a slice into an array
fn parseWordlist(comptime wordlist: []const u8) [countWordlist(wordlist)][4]u8 {
    var list: [countWordlist(wordlist)][4]u8 = undefined;
    var i: usize = 0;

    var word_iter = std.mem.tokenizeScalar(u8, wordlist, '\n');
    while (word_iter.next()) |word| {
        list[i] = @as(*const [word.len]u8, @ptrCast(word.ptr)).*;
        i += 1;
    }

    return list;
}

const words = blk: {
    @setEvalBranchQuota(1_000_000);
    break :blk parseWordlist(@embedFile("words.txt"));
};

const InvalidWordError = error{
    BadLength,
    NotInWordlist,
    NotWordLadder,
    UsedWord,
    EmptyLadder,
};

fn validateLadder(ladder: []const u8) InvalidWordError!void {
    const last_newline = std.mem.lastIndexOfScalar(u8, ladder, '\n') orelse
        return error.EmptyLadder;

    const existing = ladder[0..last_newline];
    const proposed = ladder[last_newline + 1 ..];

    const word = @as(*const [4]u8, @ptrCast(proposed.ptr)).*;

    for (words) |dict_word| {
        if (std.mem.eql(u8, &dict_word, &word)) break;
    } else return error.NotInWordlist;

    var word_iter = std.mem.tokenizeScalar(u8, existing, '\n');
    var prev: [4]u8 = undefined;
    var count: usize = 0;

    while (word_iter.next()) |raw_word| {
        if (raw_word.len != 4) return error.BadLength;
        const existing_word = @as(*const [4]u8, @ptrCast(raw_word.ptr)).*;

        for (words) |dict_word| {
            if (std.mem.eql(u8, &dict_word, &existing_word)) break;
        } else return error.NotInWordlist;

        if (count > 0) {
            var diff: u32 = 0;
            for (prev, existing_word) |a, b| {
                if (a != b) diff += 1;
            }
            if (diff != 1) return error.NotWordLadder;
        }

        if (std.mem.eql(u8, &existing_word, &word)) return error.UsedWord;

        prev = existing_word;
        count += 1;
    }

    var diff: u32 = 0;
    for (word, prev) |a, b| {
        if (a != b) diff += 1;
    }
    if (diff != 1) return error.NotWordLadder;
}

fn handleConnection(random: std.Random, conn: std.net.Server.Connection) !void {
    // Define connection reader and writer buffers.
    // Similar to stdout & stdin writers and readers, we use buffers for performance
    // considerations for networking streams as well.
    var conn_reader_buf: [1024]u8 = undefined;
    var conn_writer_buf: [1024]u8 = undefined;
    var conn_reader = conn.stream.reader(&conn_reader_buf);
    var conn_writer = conn.stream.writer(&conn_writer_buf);

    // std.http.Server can technically wrap any type of reader and writer.
    // We supply a TCP connection.
    // Initiliaze a HTTP server with conn reader and writer buffers.
    // The returned server is ready for receiveHead to be called.
    var http_server = std.http.Server.init(
        conn_reader.interface(),
        &conn_writer.interface,
    );

    // Parsing the request once read.
    var request = try http_server.receiveHead();

    // Any error being happened after this point is a server's fault, not the client's.
    // errdefer is a special kind of defer, which executes only when an error is returned.
    // An important caveat is that you cannot return an error within an errdefer, so if
    // our response fails, we will not fallback on anything else. This behavior is sensible
    // for our case, though.
    errdefer request.respond("", .{
        .status = .internal_server_error,
    }) catch {};

    if (request.head.method == .GET and
        std.mem.eql(u8, request.head.target, "/"))
    {
        try request.respond(@embedFile("ladder.html"), .{
            .extra_headers = &.{
                .{ .name = "Content-Type", .value = "text/html" },
            },
        });
    } else if (request.head.method == .GET and
        std.mem.eql(u8, request.head.target, "/first"))
    {
        const start_index = random.intRangeLessThan(usize, 0, words.len);
        const start = words[start_index];
        try request.respond(&start, .{});
    } else if (request.head.method == .POST and
        std.mem.eql(u8, request.head.target, "/ladder"))
    {
        var reader_buf: [1024]u8 = undefined;
        const reader = try request.readerExpectContinue(&reader_buf);
        const text = try reader.takeDelimiterExclusive(0);

        validateLadder(text) catch |e| {
            try request.respond(@errorName(e), .{ .status = .bad_request });
            return;
        };

        try request.respond("", .{});
    } else {
        try request.respond("", .{ .status = .not_found });
    }
}

pub fn main() !void {
    const addr = std.net.Address.initIp4(.{ 127, 0, 0, 1 }, 8000);
    var tcp_server = try addr.listen(.{ .reuse_address = true });

    const seed: u64 = @intCast(std.time.milliTimestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();

    serve: while (true) {
        const conn = tcp_server.accept() catch |e| {
            std.log.err("accept: {}", .{e});
            continue :serve;
        };
        defer conn.stream.close();

        // By putting all of that behaviour in a function, we can simplify our error handling-
        // code significantly.
        handleConnection(random, conn) catch |e| {
            std.log.err("handleConnection: {}", .{e});
        };
    }
}
