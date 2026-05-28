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
};

// Given the previous word, verify the user's input is a valid four-letter word.
// If it is invalid, return an error.
fn validateWord(input: []const u8, ladder: []const [4]u8) InvalidWordError![4]u8 {
    // check for it is already 4-letter or not
    if (input.len != 4) {
        return error.BadLength;
    }

    const word = @as(*const [4]u8, @ptrCast(input.ptr)).*;

    // If for loop consumes all elements and doesn't break then jump to else clause.
    // For loop in Zig is an expression so it returns a value.
    for (words) |wordlist_word| {
        // compare each word from dictionary to input in order to validate.
        if (std.mem.eql(u8, &wordlist_word, &word)) {
            break;
        }
    } else {
        return error.NotInWordlist;
    }

    // Check if input word is already in the ladder. Prevents word repetition.
    for (ladder) |used_word| {
        if (std.mem.eql(u8, &used_word, &word)) {
            return error.UsedWord;
        }
    }

    const last_word = ladder[ladder.len - 1];

    var difference: u32 = 0;
    for (word, last_word) |char_w, char_lw| {
        if (char_w != char_lw) {
            difference += 1;
        }
    }

    // Given input can only be different 1 char at a time than previous word.
    if (difference != 1) {
        return error.NotWordLadder;
    }

    return word;
}

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}).init;
    defer _ = gpa.deinit();
    const ally = gpa.allocator();

    var stdout_buffer: [1024]u8 = undefined;
    var stdin_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buffer);
    const stdout = &stdout_writer.interface;
    const stdin = &stdin_reader.interface;

    const seed: u64 = @intCast(std.time.milliTimestamp());
    var prng = std.Random.DefaultPrng.init(seed);
    const random = prng.random();
    const start_index = random.intRangeLessThan(usize, 0, words.len);
    const start = words[start_index];

    var ladder = std.ArrayList([4]u8).empty;
    defer ladder.deinit(ally);

    try ladder.append(ally, start);
    try stdout.print("Let's make a word ladder! Type 'end' to exit.\n", .{});
    try stdout.flush();

    while (true) {
        try stdout.print("The ladder is {d} words long. The last word was {s}.\n", .{ ladder.items.len, ladder.getLast() });
        try stdout.print("> ", .{});
        try stdout.flush();

        const input = try stdin.takeDelimiterExclusive('\n');

        if (std.mem.eql(u8, input, "end")) {
            try stdout.print("Bye bye!\n", .{});
            break;
        }

        const word = validateWord(input, ladder.items) catch |e| {
            const msg: []const u8 = switch (e) {
                error.BadLength => "Hey, that's not four characters!",
                error.NotInWordlist => "I don't think that's a word.",
                error.NotWordLadder => "That doesn't make a word ladder.",
                error.UsedWord => "Do not use the same word again!",
            };

            try stdout.print("{s}\n", .{msg});

            continue;
        };
        try ladder.append(ally, word);
    }
    try stdout.flush();
}
