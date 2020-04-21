`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// University: Politecnico di Milano
//
// Authors in alphabetical order:
// (1) KOTSABA MYKHAYLO  <mykhaylo.kotsaba@mail.polimi.it>
// (2) MELACARNE ENRICO  <enrico.melacarne@mail.polimi.it>
//
// Create Date: 23.02.2020 18:18:08
// Design Name: lampFPU
// Module Name: lampFPU_Sqrt
// Project Name: lampFPU Square Root Function
// Target Devices: xc7a100tcsg324-1 
//
// Description: 
// Main module of our project. Sqrt module calculate the exponent value, the 
// right value to give to the fractSqrt module and then take care of the normalization process.
// Special cases are also handled here.
//
//////////////////////////////////////////////////////////////////////////////////

module lampFPU_sqrt(
    // Timing Signals
    clk, rst,
    // Inputs
    doSqrt_i, doInvSqrt_i,
    s_i, extF_i, extE_i, nlz_i,
    isZ_i, isInf_i, isSNAN_i, isQNAN_i,
    // Outputs
    s_res_o, e_res_o, f_res_o, valid_o,
    isOverflow_o,isUnderflow_o, isToRound_o
    );


import lampFPU_pkg::*;

///////////////////////////////////////////////////////////////////////////////////////
// Timing Signals
///////////////////////////////////////////////////////////////////////////////////////
input                                  clk;
input                                  rst;

///////////////////////////////////////////////////////////////////////////////////////
// Inputs
///////////////////////////////////////////////////////////////////////////////////////
input                                  doSqrt_i;
input                                  doInvSqrt_i;
input [LAMP_FLOAT_S_DW-1:0]			   s_i;
input [(1+LAMP_FLOAT_F_DW)-1:0]		   extF_i;
input [(LAMP_FLOAT_E_DW+1)-1:0]		   extE_i;
input [$clog2(LAMP_FLOAT_F_DW+1)-1:0]  nlz_i;
input								   isZ_i;
input								   isInf_i;
input								   isSNAN_i;
input								   isQNAN_i;

///////////////////////////////////////////////////////////////////////////////////////
// Outputs
///////////////////////////////////////////////////////////////////////////////////////
output	logic						   s_res_o;
output	logic [LAMP_FLOAT_E_DW-1:0]	   e_res_o;
output	logic [LAMP_FLOAT_F_DW+5-1:0]  f_res_o;
output	logic						   valid_o;
output	logic						   isOverflow_o;
output	logic						   isUnderflow_o;
output	logic						   isToRound_o;

///////////////////////////////////////////////////////////////////////////////////////
// Internal Wires
///////////////////////////////////////////////////////////////////////////////////////
logic [LAMP_FLOAT_S_DW-1:0]			   s_r;
logic [(1+LAMP_FLOAT_F_DW)-1:0]		   extF_r;
logic [(LAMP_FLOAT_E_DW+1)-1:0]		   extE_r;
logic								   isZ_r;
logic								   isInf_r;
logic								   isSNAN_r;
logic								   isQNAN_r;
logic								   doSqrt_r;
logic								   doInvSqrt_r;

logic						           s_res;
logic [LAMP_FLOAT_E_DW-1:0]	           e_res;
logic [LAMP_FLOAT_F_DW+5-1:0]	       f_res;
logic						   	       valid;
logic							       isOverflow;
logic							       isUnderflow;
logic						           isToRound;

logic [LAMP_FLOAT_E_DW-1:0]	           e_res_postNorm, e_res_preNorm_r, e_res_preNorm;
logic [LAMP_FLOAT_F_DW+5-1:0]	       f_res_postNorm;
logic [2*(1+LAMP_FLOAT_F_DW)-1:0]      f_res_preNorm;
logic                                  stickyBit;

logic			   					   isCheckNanInfValid;
logic								   isZeroRes;
logic								   isCheckInfRes;
logic								   isCheckNanRes;
logic								   isCheckSignRes;

///////////////////////////////////////////////////////////////////////////////////////
// FractSqrt Signals
///////////////////////////////////////////////////////////////////////////////////////
logic                                  fs_doSqrt;
logic                                  fs_doInvSqrt;
logic [(1+LAMP_FLOAT_F_DW+1)-1:0]      fs_f;
logic [2*(1+LAMP_FLOAT_F_DW)-1:0]      fs_result;
logic                                  fs_valid;

///////////////////////////////////////////////////////////////////////////////////////
// FractSqrt Module Istantiation
///////////////////////////////////////////////////////////////////////////////////////
lampFPU_fractSqrt lampFPU_fractSqrt0 (
        .clk         (clk),
        .rst         (rst),
        .doSqrt_i    (fs_doSqrt),
        .doInvSqrt_i (fs_doInvSqrt),
        .f_i         (fs_f),
        .result_o    (fs_result),
        .valid_o     (fs_valid)
    );

///////////////////////////////////////////////////////////////////////////////////////
// Sequential Logic
///////////////////////////////////////////////////////////////////////////////////////
always_ff @(posedge clk)
begin
    if(rst)
    begin
        s_r             <= '0;
        isZ_r           <= '0;
        isInf_r         <= '0;
        isSNAN_r        <= '0;
        isQNAN_r        <= '0;
        doSqrt_r        <= '0;
        doInvSqrt_r     <= '0;
        e_res_preNorm_r <= '0;
        s_res_o         <= '0;
        e_res_o         <= '0;
        f_res_o         <= '0;
        valid_o         <= '0;
        isOverflow_o    <= '0;
        isUnderflow_o   <= '0;
        isToRound_o     <= '0;
    end
    else
    begin
        s_r             <= s_i;
        isZ_r           <= isZ_i;
        isInf_r         <= isInf_i;
        isSNAN_r        <= isSNAN_i;
        isQNAN_r        <= isQNAN_i;
        if(doSqrt_i|doInvSqrt_i) begin
            doSqrt_r        <= doSqrt_i;         // It was necessary to sample the input value of doSqrt/doInvSqrt 
            doInvSqrt_r     <= doInvSqrt_i;      // for the special condition detection part to work properly
        end
        e_res_preNorm_r <= e_res_preNorm;
        s_res_o         <= s_res;
        e_res_o         <= e_res;
        f_res_o         <= f_res;
        valid_o         <= valid;
        isOverflow_o    <= isOverflow;
        isUnderflow_o   <= isUnderflow;
        isToRound_o     <= isToRound;
    end
end

///////////////////////////////////////////////////////////////////////////////////////
// Wire Assignement
///////////////////////////////////////////////////////////////////////////////////////
assign fs_doSqrt    = doSqrt_i;
assign fs_doInvSqrt = doInvSqrt_i;
assign f_res_preNorm = fs_result;

///////////////////////////////////////////////////////////////////////////////////////
// Combinational logic for mantissa computation (F) --preFractSqrt --preNorm
///////////////////////////////////////////////////////////////////////////////////////
always_comb
begin
    if( (~extE_i[0]) | nlz_i[0] ) // Even Exponent or Odd Number of Leading Zeros
        fs_f = {1'b0 , extF_i}; 
    else
        fs_f = {extF_i , 1'b0};
end

///////////////////////////////////////////////////////////////////////////////////////
// Combinational logic for exponent computation (E) --preNorm
///////////////////////////////////////////////////////////////////////////////////////
always_comb
begin
    e_res_preNorm = e_res_preNorm_r;
    if(doSqrt_i)
        e_res_preNorm =   (LAMP_FLOAT_E_BIAS-1)/2 + ((extE_i-nlz_i)>>1) + 1; 
    else if(doInvSqrt_i)
        e_res_preNorm = (3*LAMP_FLOAT_E_BIAS-3)/2 - ((extE_i-nlz_i)>>1) + 1;
end

///////////////////////////////////////////////////////////////////////////////////////
// Exponent and FractSqrt-Output Normalization
///////////////////////////////////////////////////////////////////////////////////////
always_comb
begin

    if(~f_res_preNorm[2*(1+LAMP_FLOAT_F_DW)-2])
    begin // CASE 00.1xxxx ----> 01.xxxx
        stickyBit         =|f_res_preNorm[0 +:2*(1+LAMP_FLOAT_F_DW)-(LAMP_FLOAT_F_DW+5-1)-1];
        f_res_postNorm    = f_res_preNorm[2*(1+LAMP_FLOAT_F_DW)-1-1 -: LAMP_FLOAT_F_DW+5];
        e_res_postNorm    = e_res_preNorm_r - 1;
    end
    else
    begin // CASE 01.xxxxx ----> 01.xxxx
        stickyBit         =|f_res_preNorm[0 +:2*(1+LAMP_FLOAT_F_DW)-(LAMP_FLOAT_F_DW+5-1)];
        f_res_postNorm    = f_res_preNorm[2*(1+LAMP_FLOAT_F_DW)-1 -: LAMP_FLOAT_F_DW+5];
        e_res_postNorm    = e_res_preNorm_r;
    end
    
    f_res_postNorm[1]  = f_res_postNorm[1] | stickyBit;
    f_res_postNorm[0]  = stickyBit;
    
end

///////////////////////////////////////////////////////////////////////////////////////
// Special Conditions Detection and Output Generation
///////////////////////////////////////////////////////////////////////////////////////
always_comb
begin

    {isCheckNanInfValid, isZeroRes, isCheckInfRes, isCheckNanRes, isCheckSignRes} = FUNC_calcInfNanZeroResSqrt(isZ_r, isInf_r, s_r, isSNAN_r, isQNAN_r, doSqrt_r, doInvSqrt_r);

    unique if (isZeroRes)
        {s_res, e_res, f_res} = {isCheckSignRes, ZERO_E_F, 5'b0};
    else if (isCheckInfRes)
        {s_res, e_res, f_res} = {isCheckSignRes, INF_E_F,  5'b0};
    else if (isCheckNanRes) 
        {s_res, e_res, f_res} = {isCheckSignRes, QNAN_E_F, 5'b0};
    else
        {s_res, e_res, f_res} = {isCheckSignRes, e_res_postNorm[LAMP_FLOAT_E_DW-1:0], f_res_postNorm};

    valid       = fs_valid;
    isToRound   = ~isCheckNanInfValid;
    isOverflow  = 1'b0;
    isUnderflow = 1'b0;

end


endmodule
