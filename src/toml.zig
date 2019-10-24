const std = @import("std");
const testing = std.testing;
const mem = std.mem;
const ascii = std.ascii;

// Removoe later
const warn = std.debug.warn;

const QuoteTracker = struct {
    const Self = @This();
    const QuoteType = enum {
        Single,
        Double,
        // TODO(hazebooth)): multiline
        // Multiline
    };

    currentlyWithin: ?QuoteType,

    // TOOD(hazebooth): turn into union
    const Event = union(enum) {
        Enter: QuoteType,
        Exit: QuoteType,
        None,
    };

    fn process(self: *Self, source: []const u8, index: usize) Event {
        const escaped = if (index > 1) source[index - 1] == '\\' else false;
        // TODO(hazebooth): evaluate naiveness
        const c = source[index];
        if (!escaped) {
            if (c == '"' and !self.inString()) { // start double quote
                self.currentlyWithin = QuoteType.Double;
                return Event{ .Enter = self.currentlyWithin.? };
            } else if (c == '"' and self.isInDoubleQuoteString()) { // end double quote
                self.currentlyWithin = null;
                return Event{ .Exit = QuoteType.Double };
            } else if (c == '\'' and !self.inString()) { // start single quote
                self.currentlyWithin = QuoteType.Single;
                return Event{ .Enter = self.currentlyWithin.? };
            } else if (c == '\'' and self.isInSingleQuoteString()) { // end single quote}
                self.currentlyWithin = null;
                return Event{ .Exit = QuoteType.Single };
            }
        }
        return Event.None;
    }

    fn inString(self: Self) bool {
        return self.currentlyWithin != null;
    }

    fn isInStringOfQuoteType(self: Self, ty: QuoteType) bool {
        return self.inString() and self.currentlyWithin.? == ty;
    }

    fn isInSingleQuoteString(self: Self) bool {
        return self.isInStringOfQuoteType(QuoteType.Single);
    }

    fn isInDoubleQuoteString(self: Self) bool {
        return self.isInStringOfQuoteType(QuoteType.Double);
    }

    fn new() Self {
        return Self{
            .currentlyWithin = null,
        };
    }
};

pub const StrKV = struct {
    const Self = @This();

    key: []const u8,
    value: []const u8,

    fn eqlBare(self: Self, key: []const u8, value: []const u8) bool {
        return mem.eql(u8, self.key, key) and mem.eql(u8, self.value, value);
    }

    fn eql(self: Self, other: Self) bool {
        return self.eqlBare(other.key, other.value);
    }
};

pub const Token = union(enum) {
    TableDefinition: []const u8,
    KeyValue: StrKV,
};

const State = enum {
    Root,
    Key,
    QuoteKey,
    Value,
    TableDefinition,
};

pub const Parser = struct {
    const Self = @This();

    state: State,
    allocator: *mem.Allocator,
    source: []const u8,

    index: usize,
    lagIndex: usize,
    processed: usize,

    quoteTracker: QuoteTracker,

    key: ?[]const u8,

    pub fn init(allocator: *mem.Allocator, source: []const u8) Parser {
        return Parser{
            .state = .Root,
            .allocator = allocator,
            .source = source,
            .index = 0,
            .lagIndex = 0,
            .quoteTracker = QuoteTracker.new(),
            .processed = 0,
            .key = null,
        };
    }

    fn setState(self: *Self, state: State) void {
        // warn("{} => {}\n", self.state, state);
        self.state = state;
    }

    // skipToNewline will jump over everything from where it was
    // until the next newline. if none exists, the parser sets itself
    // to the end of the source
    fn skipToNewline(self: *Self) void {
        if (mem.indexOfScalar(u8, self.source[self.index..], '\n')) |newLineIndex| {
            // warn("nl comment jump\n");
            self.index += newLineIndex + 1;
        } else {
            // warn("eof comment jump\n");
            self.index = self.source.len;
        }
        self.lagIndex = self.index;
    }

    // process increments the index of the parser and transforms the
    // state of the parser if a transition criteria is found.
    // if no transition criteria is found, process will return false to
    // signal to stop processing.
    fn process(self: *Self, tokens: *std.ArrayList(Token)) !bool {
        const char = self.source[self.index];

        const isNewline = char == '\n';
        const isComment = char == '#';

        const eof = self.index == self.source.len - 1;
        // const isEscaped = if (self.index > 1) self.source[self.index - 1] == '\\' else false;
        // if (!isEscaped) self.processQuote(char);
        const quoteEvent = self.quoteTracker.process(self.source, self.index);
        // if (isNewline) {
        //     warn("on <newline> ({})\n", self.index);
        // } else warn("on {c} ({})\n", char, self.index);
        switch (self.state) {
            // we are at the default state,
            .Root => {
                // whitespace can exist
                switch (quoteEvent) {
                    .Enter => {
                        self.setState(.QuoteKey);
                    },
                    else => {
                        if (char == '[') {
                            self.setState(.TableDefinition);
                        } else if (ascii.isSpace(char)) {
                            // cont
                        } else if (isComment) {
                            // we hit a comment, skip to next line
                            self.skipToNewline();
                        } else if (isValidKeyChar(char)) {
                            self.setState(.Key);
                        } else return error.UnexpectedCharacter;
                    },
                }
            },
            .QuoteKey => {
                switch (quoteEvent) {
                    .Exit => {
                        self.setState(.Key);
                    },
                    .Enter => unreachable,
                    .None => {},
                }
            },
            .Key => {
                if (char == '=') {
                    self.key = self.source[self.lagIndex..self.index];
                    self.lagIndex = self.index;
                    self.setState(.Value);
                } else if (!isValidKeyChar(char)) return error.UnexpectedCharacter;
            },
            .Value => {
                if (isNewline or (!self.quoteTracker.inString() and isComment) or eof) {
                    if (self.key) |k| {
                        const end = b: {
                            if (isNewline or isComment) {
                                break :b self.index;
                            } else break :b self.index + 1;
                        };
                        const value = self.source[self.lagIndex + 1 .. end];
                        const strippedKey = stripWhitespace(k);
                        if (strippedKey.len == 0) return error.BadKey;
                        const strippedValue = stripWhitespace(value);
                        if (!isValidValue(strippedValue)) return error.BadValue;
                        const token = Token{
                            .KeyValue = StrKV{
                                .key = strippedKey,
                                .value = strippedValue,
                            },
                        };
                        try tokens.append(token);
                        self.key = null;
                        self.lagIndex = b: {
                            if (isNewline or isComment) {
                                break :b self.index + 1;
                            }
                            break :b self.index;
                        };
                        // if we hit a comment, we have to push the index
                        // to the next newline
                        if (isComment) {
                            // warn("comment jump window:\n{{{}}}\n", self.source[self.index..]);
                            if (mem.indexOfScalar(u8, self.source[self.index..], '\n')) |newLineIndex| {
                                self.index += newLineIndex;
                                self.lagIndex = self.index + 1;
                            }
                        }
                        self.setState(.Root);
                    } else unreachable;
                }
                // } else if (!self.withinString() and isComment) {
                //     self.skipToNewline();
                // }
            },
            .TableDefinition => {
                if (char == ']') {
                    const tableName = self.source[self.lagIndex + 1 .. self.index];
                    try tokens.append(Token{ .TableDefinition = tableName });
                    self.lagIndex = self.index;
                    self.setState(.Root);
                }
            },
        }
        self.index += 1;
        return self.index < self.source.len;
    }

    pub fn lex(self: *Self) ![]Token {
        var tokens = std.ArrayList(Token).init(self.allocator);
        while (try self.process(&tokens)) {}
        return tokens.toOwnedSlice();
    }
};

fn stripWhitespace(source: []const u8) []const u8 {
    return mem.trim(u8, source, " ");
}
// solely for parsing
fn isValidKeyChar(char: u8) bool {
    const isDash = char == '_' or char == '-';
    const isQuote = char == '"' or char == '\'';
    return ascii.isSpace(char) or ascii.isAlpha(char) or ascii.isDigit(char) or isDash or isQuote;
}

fn isValidValueString(value: []const u8) bool {
    // if the first char isnt a quote
    if (value[0] != '"' and value[0] != '\'') return false;
    if (value[0] == '"' and value[value.len - 1] != '"') return false;
    if (value[0] == '\'' and value[value.len - 1] != '\'') return false;
    // fast path over, iteratre and maintain stack to make sure

    var level: usize = 0;
    var n: usize = 0;
    var t = QuoteTracker.new();
    var enteredString = false;
    while (n < value.len) : (n += 1) {
        const ev = t.process(value, n);
        switch (ev) {
            .Enter => {
                if (enteredString) unreachable; // cant enter string while entered
                enteredString = true;
            },
            .Exit => {
                if (enteredString) {
                    // we should exit the string at the end of the value
                    // TODO(hazebooth): support multiline
                    return n == (value.len - 1);
                } else unreachable;
            },
            .None => {}, // do nothing
        }
    }
    return false;
}

fn isValidValueBoolean(value: []const u8) bool {
    return ascii.eqlIgnoreCase(value, "true") or ascii.eqlIgnoreCase(value, "false");
}

fn isValidValue(value: []const u8) bool {
    const empty = value.len == 0;
    return !empty and (isValidValueString(value) or isValidValueBoolean(value));
}
