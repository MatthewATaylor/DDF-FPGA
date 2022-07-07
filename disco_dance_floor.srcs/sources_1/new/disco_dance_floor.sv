`timescale 1ns / 1ps

module disco_dance_floor#(
    parameter LED_ROWS = 72,
    parameter LED_COLS = 165,
    parameter LED_CHANNELS = 3,
    parameter CHANNEL_BITS = 8,
    parameter CHUNK_ROWS = 8,
    parameter CHUNK_COLS = 55,
    parameter NUM_CHUNKS = 27,
    parameter BITS_PER_CHUNK = 10560  // 8 * 55 * 3 * 8
) (
    input logic clk,
    
    // Ethernet PHY
    input logic eth_crsdv,
    input logic[1:0] eth_rxd,
    output logic eth_clk,
    
    output logic[NUM_CHUNKS-1:0] led
);
    logic init = 1;

    logic led_clk;
    logic[NUM_CHUNKS-1:0] current_bits;
    
    logic will_reset;
    logic is_resetting;
    
    // Indexing
    logic[13:0] next_bit_index;  // Serves as BRAM address offset (max = BITS_PER_CHUNK - 1)
    logic[13:0] bit_cycles;  // Controls pulse on/off and reset

    // BRAM port A (write)
    logic[14:0] bram_wr_addr;
    logic[NUM_CHUNKS-1:0] bram_din;
    logic bram_wea;
    
    // BRAM port B (read)
    logic[13:0] bram_rd_addr_start;  // Either 0 or BITS_PER_CHUNK depending on active buffer
    logic[14:0] bram_rd_addr;
    logic[NUM_CHUNKS-1:0] bram_dout;
    
    always @ (posedge(led_clk)) begin
        if (init) begin
            led <= 0;
        
            will_reset <= 0;
            is_resetting <= 0;
            
            next_bit_index <= 0;
            bit_cycles <= 0;
            
            bram_rd_addr <= 0;
            
            init <= 0;
        end
        else begin
            if (is_resetting) begin
                // >50us reset between frames
                if (bit_cycles == 2000) begin
                    bit_cycles <= 0;
                    is_resetting <= 0;
                    // TODO - set bram_rd_addr_start (only write to other half of BRAM)
                end
                else begin
                    bit_cycles <= bit_cycles + 1;
                end
            end
            else begin
                if (bit_cycles == 25) begin
                    // End of bit write
                    bit_cycles <= 0;
                    
                    if (will_reset) begin
                        is_resetting <= 1;
                    end
                    will_reset <= 0;
                end
                else begin
                    if (bit_cycles == 0) begin
                        // Start of pulse - set output pins high, store bit values
                        led <= {NUM_CHUNKS{1'b1}};
                        current_bits <= bram_dout;
                        next_bit_index <= next_bit_index + 1;
                    end
                    else if (bit_cycles == 8) begin
                        // End of pulse for 0 bits
                        led <= current_bits;
                    end
                    else if (bit_cycles == 16) begin
                        // End of pulse for 1 bits
                        led <= 0;
                        
                        // Set BRAM read address for next bit
                        if (next_bit_index == BITS_PER_CHUNK) begin
                            // Finished full chunk, will need to reset
                            bram_rd_addr <= bram_rd_addr_start;
                            will_reset <= 1;
                        end
                        else begin
                            bram_rd_addr <= bram_rd_addr_start + next_bit_index;
                        end
                    end
                    bit_cycles <= bit_cycles + 1;
                end
            end
        end
    end
    
    // Generate 20MHz clock for LED interface (to help satisfy timing requirements)
    clk_wiz_1 led_clk_gen(
        .clk_in1(clk),
        .clk_out1(led_clk)
    );

    eth#(
        .NUM_CHUNKS(NUM_CHUNKS),
        .BITS_PER_CHUNK(BITS_PER_CHUNK)
    ) e(
        .clk_i(clk),
        .crsdv_i(eth_crsdv),
        .rxd_i(eth_rxd),
        .clk_o(eth_clk),
        
        .bram_rd_addr_start_o(bram_rd_addr_start),
        .led_is_resetting_i(is_resetting),
        
        .bram_wr_addr_o(bram_wr_addr),
        .bram_wea_o(bram_wea),
        .bram_d_o(bram_din)
    );
    
    blk_mem_gen_0 bram(
        .addra(bram_wr_addr), .clka(clk), .dina(bram_din), .wea(bram_wea),
        .addrb(bram_rd_addr), .clkb(clk), .doutb(bram_dout)
    );
endmodule
