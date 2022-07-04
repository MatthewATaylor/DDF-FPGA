`timescale 1ns / 1ps

module eth(
    input logic clk_i,
    input logic crsdv_i,
    input logic[1:0] rxd_i,
    output logic clk_o,
    output logic mon_clk_o,
    output logic mon_d_o
);
    enum {WAIT, PRE, INDEX, DATA, POST} state = WAIT;
    
    logic[671:0] eth_buff = 0;
    logic[9:0] eth_buff_index = 0;
    
    logic[9:0] mon_counter = 0;
    
    always @ (posedge(clk_o)) begin
        if (crsdv_i) begin
            // Ethernet PHY is receiving bits
            if (eth_buff_index < 671) begin
                eth_buff[eth_buff_index] <= rxd_i[0];
                eth_buff[eth_buff_index + 1] <= rxd_i[1];
                eth_buff_index <= eth_buff_index + 2;
            end
        end
        else begin
            eth_buff_index <= 0;
        end
    end
    
    always @ (posedge(mon_clk_o)) begin
        mon_d_o <= eth_buff[mon_counter];
        if (mon_counter == 671) begin
            mon_counter <= 0;
        end
        else begin
            mon_counter <= mon_counter + 1;
        end
    end
    
    clk_wiz_0 eth_clk_gen(
        .clk_in1(clk_i),
        .clk_out1(clk_o)
    );
    
    clk_wiz_2 eth_mon_clk_gen(
        .clk_in1(clk_i),
        .clk_out1(mon_clk_o)
    );
endmodule
