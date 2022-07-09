`timescale 1ns / 1ps

module eth#(
    parameter NUM_CHUNKS = 27,  // Note: changing this may break things
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
    logic[5:0] buff_index;  // [0, 2*NUM_CHUNKS-1 = 53]
    logic[9:0] bit_counter;
    logic[4:0] led_bit_counter;  // [0, 3*8-1 = 23]
    
    logic should_swap_bram;  // Swap BRAM blocks after led_index 439 and led_is_resetting
    logic should_write_bram;  // Set bram_wea_o high on next clock cycle
    logic is_first_buffer_block;  // Buffer block to write to on next clock cycle
    
    logic prev_crsdv;
    logic can_read_packet;  // Can only read packet if rising edge of crsdv_i is seen
    
    logic has_started_buffer_write;  // Only start when LED index 0 has been hit
    
    always @ (posedge(clk_o)) begin
        if (init) begin
            // Output ports
            bram_rd_addr_start_o <= 0;
            bram_wr_addr_o <= 0;
            bram_wea_o <= 0;
            bram_d_o <= 0;
        
            data_buff <= 0;
            led_index <= 0;
            
            buff_index <= 0;
            bit_counter <= 0;
            led_bit_counter <= 0;
            
            should_swap_bram <= 0;
            should_write_bram <= 0;
            is_first_buffer_block <= 0;
            
            prev_crsdv <= 1;
            can_read_packet <= 0;
            
            has_started_buffer_write <= 0;
            
            init <= 0;
        end
        else begin
            if (should_write_bram) begin
                // Runs the cycle after half of data_buff has been filled
                bram_wea_o <= 1;
                should_write_bram <= 0;
                
                if (is_first_buffer_block) begin
                    bram_d_o <= data_buff[NUM_CHUNKS-1:0];
                end
                else begin
                    bram_d_o <= data_buff[(NUM_CHUNKS << 1)-1:NUM_CHUNKS];
                end
            end
            
            if (bram_wea_o) begin
                bram_wea_o <= 0;  // Hold write enable for only one cycle
            end
            
            if (should_swap_bram) begin
                if (led_is_resetting_i) begin
                    // BRAM not being read or written to
                    // Set read buffer as most recently updated BRAM block
                    // Start writing to the other block
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
                                if (has_started_buffer_write || led_index == 0) begin
                                    // Wait until an led_index of 0 is seen, then begin
                                    has_started_buffer_write <= 1;
                                
                                    // Receive two bits per cycle
                                    data_buff[buff_index] <= rxd_i[0];
                                    data_buff[buff_index + 1] <= rxd_i[1];
                                    
                                    if (buff_index == NUM_CHUNKS - 1 || buff_index == (NUM_CHUNKS << 1) - 2) begin
                                        // NUM_CHUNKS bits have been received and placed on half of the buffer
                                        // Write this half-buffer to BRAM and start filling up other half-buffer
                                        
                                        // Set write address now (whichever BRAM block isn't being read)
                                        if (bram_rd_addr_start_o == 0) begin
                                            bram_wr_addr_o <= led_index * 24 + led_bit_counter + BITS_PER_CHUNK;
                                        end
                                        else begin
                                            bram_wr_addr_o <= led_index * 24 + led_bit_counter;
                                        end
                                        
                                        // Set write data and enable on next clock cycle
                                        // (Have to wait for this cycle's data to get on buffer)
                                        should_write_bram <= 1;
                                        is_first_buffer_block = (buff_index == NUM_CHUNKS - 1);
                                        
                                        led_bit_counter <= led_bit_counter + 1;
                                    end
                                    
                                    if (buff_index == (NUM_CHUNKS << 1) - 2) begin
                                        buff_index <= 0;
                                    end
                                    else begin
                                        buff_index <= buff_index + 2;
                                    end
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
                    // crsdv_i == 0 (no data on rxd_i)
                    bit_counter <= 0;
                    led_bit_counter <= 0;
                    can_read_packet <= 0;
                    if (led_index == 439 && has_started_buffer_write) begin
                        should_swap_bram <= 1;
                        led_index <= 0;
                        has_started_buffer_write <= 0;
                    end
                end
            end
            
            prev_crsdv <= crsdv_i;
        end
    end
    
    // Generate 50MHz clock for Ethernet
    clk_wiz_0 eth_clk_gen(
        .clk_in1(clk_i),
        .clk_out1(clk_o)
    );
endmodule
