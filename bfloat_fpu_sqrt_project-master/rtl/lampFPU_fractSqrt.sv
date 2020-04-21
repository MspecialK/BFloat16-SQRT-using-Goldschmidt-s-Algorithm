`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
// University: Politecnico di Milano
//
// Authors in alphabetical order: 
// (1) KOTSABA MYKHAYLO  <mykhaylo.kotsaba@mail.polimi.it>
// (2) MELACARNE ENRICO  <enrico.melacarne@mail.polimi.it>
// 
// Create Date: 03/17/2020 06:38:45 PM
// Design Name: lampFPU
// Module Name: lampFPU_fractSqrt
// Project Name: lampFPU Square Root Function
// Target Devices: xc7a100tcsg324-1 
//
// Description: 
// The fractSqrt performs both Square root and Inverse Square root of the mantissa in 9 bits [01|M] or [1|M|0]  already in input. 
// Could not working in different condition.
// 16 bit floating point number [s]|[e]|[m]  [1]|[8]|[7]
// The output is not normalized in this core, but in the sqrt module. 
// 
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

module lampFPU_fractSqrt(
        clk, rst,                             // Timing signals
        doSqrt_i, doInvSqrt_i, f_i,           // Inputs
        result_o, valid_o                     // Outputs
);

import lampFPU_pkg::*;
localparam IDLE='d0, STATE1='d1, STATE2='d2;  

//Input and Outputs
input                                           clk;        
input                                           rst;
input                                           doSqrt_i;                  //Start Sqrt operation.
input                                           doInvSqrt_i;               //Start Inverse Sqrt operation.
input           [LAMP_FLOAT_F_DW+1:0]           f_i;                       //Mantissa input.
output logic    [(2*(LAMP_FLOAT_F_DW+1)-1):0]   result_o;                  //Result that can be both, sqrt or  invSqrt.
output logic                                    valid_o;                   //Valid output bit.

//Internal wires 
logic                                                        sqrt,sqrt_next,inver,inver_next;
logic           [1:0]                                        ss,ss_nxt;                 //State counter and next_state counter. 1 bit because we have only two states.
logic           [LAMP_FLOAT_F_DW+1+LAMP_PREC_DW:0]           b,b_nxt;                     
logic           [LAMP_FLOAT_F_DW+1+LAMP_PREC_DW:0]           y,y_nxt;
logic           [2*(LAMP_FLOAT_F_DW+2+LAMP_PREC_DW)-1:0]     y_sqr,y_sqr_nxt;                    
logic           [3*(LAMP_FLOAT_F_DW+2+LAMP_PREC_DW)-1:0]     aux_b;                     //Auxiliar register to store the multiplication for the B parameter.                     
logic           [LAMP_FLOAT_F_DW+1+LAMP_PREC_DW:0]           res,res_nxt;          
logic           [2*(LAMP_FLOAT_F_DW+2+LAMP_PREC_DW)-1:0]     aux_res;                   //Auxiliar register to store the multiplication for the Result parameter.

logic           [2*(LAMP_FLOAT_F_DW+1)-1:0]                  result_o_nxt;
logic                                                        valid_o_nxt;
logic           [$clog2(LAMP_APPROX_MULS)-1:0]               i,i_nxt;                   //Counter up to five cycles. 

//////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                                SERIAL BLOCK
//////////////////////////////////////////////////////////////////////////////////////////////////////////////

always_ff @(posedge clk)
begin
if(rst)
begin 
    sqrt        <= 0;
    inver       <= 0;
    valid_o     <= 0;
    i           <= 0;
    ss          <= IDLE;
    b           <= 0;
    res         <= 0;
    y           <= 0;
    y_sqr       <= 0;
    result_o    <= 0;
end    
else
begin 
    sqrt        <= sqrt_next;
    inver       <= inver_next;
    b           <= b_nxt;
    res         <= res_nxt;
    y           <= y_nxt;
    y_sqr       <= y_sqr_nxt;
    ss          <= ss_nxt;
    i           <= i_nxt;
    valid_o     <= valid_o_nxt;
    result_o    <= result_o_nxt;
end
end
//////////////////////////////////////////////////////////////////////////////////////////////////////////////
//                                                                                         COMBINATIONAL BLOCK
//////////////////////////////////////////////////////////////////////////////////////////////////////////////

always @(*) 
begin    
b_nxt         =   b; 
y_nxt         =   y;
y_sqr_nxt     =   y_sqr;
res_nxt       =   res;
sqrt_next     =   sqrt;
inver_next    =   inver;

valid_o_nxt   =   1'b0;
ss_nxt        =   ss;
i_nxt         =   i;
result_o_nxt  =   'b0;

case (ss)
IDLE: /////////////////////////////////////////////////////////////////////////////////////// IDLE STATE
begin   
    if (doSqrt_i || doInvSqrt_i)                
    begin                  
        ss_nxt          =   STATE1; 
         
        b_nxt           =   f_i << LAMP_PREC_DW;
        y_nxt           =   FUNC_approxInvSqrt(f_i) << (LAMP_FLOAT_F_DW+1+LAMP_PREC_DW+1) - (LAMP_APPROX_DW+1);
        y_sqr_nxt       =   y_nxt*y_nxt;                             
        i_nxt           =   0;
        
        sqrt_next       =   doSqrt_i;
        inver_next      =   doInvSqrt_i;
        
    end
end
      
STATE1: ///////////////////////////////////////////////////////////////////////// COMPUTATION STATE1
begin        
               
    ss_nxt  =   STATE2;   
        
    aux_b   =   b*y_sqr;
    b_nxt   =   aux_b[3*(LAMP_FLOAT_F_DW+2+LAMP_PREC_DW)-3-:(LAMP_FLOAT_F_DW+LAMP_PREC_DW+2)];
            
    if (i == 0) begin
        aux_res=b*y;
        if(sqrt) begin
            res_nxt =  aux_res[2*(LAMP_FLOAT_F_DW+2+LAMP_PREC_DW)-2-:(LAMP_FLOAT_F_DW+LAMP_PREC_DW+2)];
        end else if (inver) begin 
            res_nxt = y; 
        end 
    end
end
STATE2: ///////////////////////////////////////////////////////////////////////// COMPUTATION STATE2
begin

    ss_nxt      =   STATE1;
    
    y_nxt       =   (2'b11<<(LAMP_FLOAT_F_DW+LAMP_PREC_DW+2-2)) - (b>>1);
    y_sqr_nxt   =   y_nxt*y_nxt;                
    aux_res     =   res*y_nxt;   // Change respect to the algorithm, we calculate the res_next 
    res_nxt     =   aux_res[2*(LAMP_FLOAT_F_DW+2+LAMP_PREC_DW)-2-:(LAMP_FLOAT_F_DW+LAMP_PREC_DW+2)];
    i_nxt       =   i+1;
    
    if (i == LAMP_APPROX_MULS - 1) begin
        ss_nxt        =   IDLE;
        valid_o_nxt   =   1'b1;   //Go back to IDLE, we set the valid_o and we are ready in the same clock cycle to start another operation
        result_o_nxt  =   aux_res[2*(LAMP_FLOAT_F_DW+2+LAMP_PREC_DW)-1-:(2*(LAMP_FLOAT_F_DW+1))];  //Returning the 16 most significant bits
    end
    
end

endcase 

end
endmodule