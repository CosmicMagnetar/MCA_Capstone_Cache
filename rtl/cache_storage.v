`timescale 1ns/1ps

module cache_storage (
    input  wire         clk,
    input  wire         reset,

    input  wire [5:0]   lookup_index,
    input  wire [1:0]   lookup_word_offset,
    output wire [21:0]  lookup_tag,
    output wire         lookup_valid,
    output wire [31:0]  lookup_word_data,

    input  wire         refill_en,
    input  wire [5:0]   refill_index,
    input  wire [21:0]  refill_tag,
    input  wire [127:0] refill_block_data,

    input  wire         word_write_en,
    input  wire [5:0]   word_write_index,
    input  wire [1:0]   word_write_offset,
    input  wire [31:0]  word_write_data
);

    // 64 cache lines, each containing:
    // 1 tag (22 bits), 1 valid bit, and 4 words (32 bits each).

    reg [21:0] tag_array [0:63];
    reg        valid_array [0:63];
    reg [31:0] data_array [0:255];

    integer i;

    // Combinational lookup
    assign lookup_tag = tag_array[lookup_index];
    assign lookup_valid = valid_array[lookup_index];

    // Four words per cache line.
    // Word 0 is stored at the lowest address.
    assign lookup_word_data =
        data_array[{lookup_index, lookup_word_offset}];

    // Synchronous reset and write operations
    always @(posedge clk) begin
        if (reset) begin
            for (i = 0; i < 64; i = i + 1) begin
                valid_array[i] <= 1'b0;
            end
        end
        else if (refill_en) begin
            tag_array[refill_index] <= refill_tag;
            valid_array[refill_index] <= 1'b1;

            data_array[{refill_index, 2'b00}] <= refill_block_data[31:0];
            data_array[{refill_index, 2'b01}] <= refill_block_data[63:32];
            data_array[{refill_index, 2'b10}] <= refill_block_data[95:64];
            data_array[{refill_index, 2'b11}] <= refill_block_data[127:96];
        end
        else if (word_write_en) begin
            data_array[{word_write_index, word_write_offset}]
                <= word_write_data;
        end
    end

endmodule
