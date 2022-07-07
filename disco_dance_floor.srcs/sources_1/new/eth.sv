`timescale 1ns / 1ps

module eth#(
    parameter NUM_CHUNKS = 27,  // Note: changing this will break things
    parameter BITS_PER_CHUNK = 10560
) (
    input logic clk_i,  // 100MHz
    input logic crsdv_i,  // Ethernet data valid
    input logic[1:0] rxd_i,  // Ethernet data (2 bits per cycle)
    output logic clk_o,  // 50MHz Ethernet clk
    
    output logic[13:0] bram_rd_addr_start_o,  // Either 0 or BITS_PER_CHUNK (write to the other one)
    input logic led_is_resetting_i,  // When resetting, can modify bram_rd_addr_start
    
    output logic[14:0] bram_wr_addr_o,
    output logic bram_wea_o,
    output logic[NUM_CHUNKS-1:0] bram_d_o
);
    // Preamble - 64 bits (0:63)
    // Dst MAC addr - 48 bits (64:111)
    // Src MAC addr - 48 bits (112:159)
    // EtherType - 16 bits (160:175)
    // LED index - 16 bits (only need 9) (176:191)
    // Data - 27 * 3 * 8 = 648 bits (192:839)
    
    logic init = 1;
    
    // Data
    logic[(NUM_CHUNKS << 1)-1:0] data_buff;
    logic[9:0] led_index;  // Bit 9 unused
    
    // Indexing
    logic[4:0] buff_start;  // Either 0 or NUM_CHUNKS
    logic[4:0] buff_index;  // [0, NUM_CHUNKS - 1]
    logic[9:0] bit_counter;
    logic[4:0] led_bit_counter;  // [0, 3*8-1 = 23]
    
    logic should_swap_bram;  // Swap BRAM blocks after led_index 439 and led_is_resetting
    
    logic prev_crsdv;
    logic can_read_packet;  // Can only read packet if rising edge of crsdv_i is seen
    
    always @ (posedge(clk_o)) begin
        if (init) begin
            // Output ports
            bram_rd_addr_start_o <= 0;
            bram_wr_addr_o <= 0;
            bram_wea_o <= 0;
            bram_d_o <= 0;
        
            data_buff <= 0;
            led_index <= 0;
            
            buff_start <= 0;
            buff_index <= 0;
            bit_counter <= 0;
            led_bit_counter <= 0;
            
            should_swap_bram <= 0;
            
            prev_crsdv <= 1;
            can_read_packet <= 0;
            
            init <= 0;
        end
        else begin
            if (bram_wea_o) begin
                bram_wea_o <= 0;  // Hold write enable for one cycle
            end
            
            if (should_swap_bram) begin
                if (led_is_resetting_i) begin
                    if (bram_rd_addr_start_o == 0) begin
                        bram_rd_addr_start_o <= BITS_PER_CHUNK;
                    end
                    else begin
                        bram_rd_addr_start_o <= 0;
                    end
                    should_swap_bram <= 0;
                end
            end
            else begin
                if (crsdv_i) begin
                    if (can_read_packet || (bit_counter == 0 && prev_crsdv == 0)) begin
                        // Only respond to high crsdv_i if rising edge was sensed
                        // Note: this means packets may be skipped, shouldn't be often enough to matter
                        if (bit_counter <= 839) begin
                            if (bit_counter >= 192) begin
                                // Data
                                
                                data_buff[buff_index + buff_start] <= rxd_i[0];
                                // Second bit may have to wrap around
                                
                                if (buff_index == NUM_CHUNKS - 1) begin
                                    if (buff_start == 0) begin
                                        buff_start <= NUM_CHUNKS;
                                        buff_index <= 1;
                                        
                                        data_buff[NUM_CHUNKS] <= rxd_i[1];
                                        bram_d_o <= data_buff[NUM_CHUNKS-1:0];
                                    end
                                    else begin
                                        buff_start <= 0;
                                        buff_index <= 0;
                                        
                                        data_buff[0] <= rxd_i[1];
                                        bram_d_o <= data_buff[(NUM_CHUNKS << 1)-1:NUM_CHUNKS];
                                    end
                                    
                                    if (bram_rd_addr_start_o == 0) begin
                                        bram_wr_addr_o <= led_index * 24 + led_bit_counter + BITS_PER_CHUNK;
                                    end
                                    else begin
                                        bram_wr_addr_o <= led_index * 24 + led_bit_counter;
                                    end
                                    bram_wea_o <= 1;
                                    
                                    led_bit_counter <= led_bit_counter + 1;
                                end
                                else begin
                                    data_buff[buff_index + buff_start + 1] <= rxd_i[1];
                                    buff_index <= buff_index + 2;
                                end
                            end
                            else if (bit_counter >= 176 && bit_counter <= 184) begin
                                // LED index
                                led_index[bit_counter - 176] <= rxd_i[0];
                                led_index[bit_counter - 175] <= rxd_i[1];
                            end
                            bit_counter <= bit_counter + 2;
                        end
                        can_read_packet <= 1;
                    end
                end
                else begin
                    bit_counter <= 0;
                    led_bit_counter <= 0;
                    can_read_packet <= 0;
                    if (led_index == 439) begin
                        should_swap_bram <= 1;
                        led_index <= 0;
                    end
                end
            end
            
            prev_crsdv <= crsdv_i;
        end
    end
    
    clk_wiz_0 eth_clk_gen(
        .clk_in1(clk_i),
        .clk_out1(clk_o)
    );
endmodule
