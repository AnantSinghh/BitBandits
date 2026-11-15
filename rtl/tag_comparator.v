// =============================================================================
// Module Name: tag_comparator
// Designer:    Ronit
// Project:     Design and Analysis of a Direct-Mapped Cache Controller
// Description: Compares stored tag from cache storage with requested address tag.
//              Considers valid bit to determine cache hit vs miss.
//              hit  = valid_stored & (tag_stored == tag_req)
//              miss = ~hit
// =============================================================================

`timescale 1ns / 1ps

module tag_comparator #(
    parameter TAG_WIDTH = 22
)(
    input  wire [TAG_WIDTH-1:0] tag_stored,
    input  wire [TAG_WIDTH-1:0] tag_req,
    input  wire                 valid_stored,
    output wire                 hit,
    output wire                 miss
);

    wire tag_match;

    assign tag_match = (tag_stored == tag_req);
    assign hit       = valid_stored & tag_match;
    assign miss      = ~hit;

endmodule
