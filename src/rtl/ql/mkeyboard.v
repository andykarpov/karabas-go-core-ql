//-----------------------------------------------------
//------- Copyright (c) Theodoulos Liontakis  2024 ----
//-----------------------------------------------------
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 
// 

module mkeyboard ( 
	input clk,
	input reset,
	output [7:0] rows_o,
	input [6:0] cols_i,
	input mbutton,
	input gbutton,
	output [63:0] omatrix,
	output [7:0] keys_o,
	input [4:0] js0,
	input [4:0] js1,
	input ps2_clk,
	input ps2_data
);



function [7:0] m;
	input [7:0] col, row;
	begin
		m = col * 8'd8 + row;
	end
endfunction

reg [63:0] matrix;
reg [63:0] qmatrix;
reg [12:0] i;
reg [7:0] rows;
reg [6:0] ncols,sdelay;
reg [7:0] keyss;
reg fkeys, exkeys;
reg BSkey,LBSkey,sft,graph,symb,dl0,mb,gb,Lmk,Lgk,keys6to0,mbs,gbc;

assign keys_o = keyss;
assign omatrix=qmatrix;
assign rows_o=rows;


// ================================= leyout =============================
// F1     ESC  1   2   3   4   5   6   7   8   9   0   -   =   Â£   \
// F2     TAB    Q   W   E   R   T   Y   U   I   O   P   [   ]
// F3     CAPS    A   S   D   F   G   H   J   K   L   ;   '      ENTER
// F4     SHIFT     Z   X   C   V   B   N   M   ,   .   /     SHIFT
// F5     CTRL  LEFT RIGHT          SPACE             UP  DOWN   ALT 


always @(posedge clk)
begin
if (reset) 
	begin
		matrix <= 64'd0;
		qmatrix <= 64'd0;
		keyss <= 8'b11111111;
		exkeys<=1'b0;
		fkeys<=1'b0;
		BSkey<=1'b0;
	end
else
	begin
	i<=i+13'd1;
	ncols= ~cols_i;
	case(i)
		  0: rows<=8'b???????0;  //row 0 
		398: matrix[7:0]<= {1'b0,ncols}; //read row 0
		400: rows<=8'b??????0?;
		798: matrix[15:8]<= {1'b0,ncols};
		800: rows<=8'b?????0??;
		1198: matrix[23:16]<={1'b0,ncols};
		1200: rows<=8'b????0???;
		1598: matrix[31:24]<= {1'b0,ncols};  
		1600: rows<=8'b???0????;
		1998: matrix[39:32]<={1'b0,ncols};
		2000: rows<=8'b??0?????;
		2398: matrix[47:40]<={1'b0,ncols};
		2400: rows<=8'b?0??????;
	    2798: matrix[55:48]<={1'b0,ncols};
		2800: rows<=8'b0???????;
		3198: matrix[63:56]<= {1'b0,ncols};
//		3200: rows<=8'b???????0;  //row 0 
//		3599: matrix[0]<=ncols[0]; //read row 0
		3600: rows<=8'b????????;
		3993: begin 
		        mb=~mbutton;   // yellow button
				gb=~gbutton;   // green button
				keys6to0<=matrix[m(4,4)] | matrix[m(4,3)] |matrix[m(4,2)] | matrix[m(4,1)] | matrix[m(4,0)];
				mbs=0; gbc=0;
			 end
		3994: begin
              if (mb & ~Lmk & keys6to0) matrix[0]=1'b1; else if (mb & Lmk & keys6to0) mbs=1;  
              if (gb & ~Lgk & keys6to0) begin matrix[m(1,6)]=1'b1; matrix[0]=1'b1; end else if (gb & Lgk & keys6to0) gbc=1;
		      end
		3995: begin
		        Lmk=mb; Lgk=gb;
				//fkeys <= matrix[3*8+0] | matrix[3*8+1] | matrix[3*8+2] | matrix[3*8+3] | matrix[3*8+4];
				exkeys <=  matrix[m(7,1)] | mb | mbs | gbc| gb;
				if (~LBSkey & matrix[6*8+5]) begin
					matrix[m(1,6)]<=1'b1;
					LBSkey<=matrix[6*8+5];
				end else begin
					BSkey <= matrix[6*8+5];
					LBSkey<=matrix[6*8+5];
				end
				symb=matrix[m(7,1)];
			  end 
		3996: begin
				if (!matrix[m(3,6)] & !(symb & matrix[m(7,4)]) & !(symb & matrix[m(0,3)]) & !(symb & matrix[m(1,1)])
				  & !matrix[m(4,6)] & !(symb & matrix[m(1,0)]) & !(symb & matrix[m(1,3)]) & !(symb & matrix[m(1,4)])
				                    & !(symb & matrix[m(0,1)]) & !(symb & matrix[m(2,3)]) & !(symb & matrix[m(2,4)]) 
				                    & !(symb & matrix[m(6,4)]) & !(symb & matrix[m(6,2)]))
				     sdelay=50; else if (sdelay>0) sdelay<=sdelay-1; 
			 end 
		3997: begin
				if ( matrix[m(3,6)] | (symb & matrix[m(7,4)]) | (symb & matrix[m(0,3)]) | (symb & matrix[m(1,1)])
				   | matrix[m(4,6)] | (symb & matrix[m(1,0)]) | (symb & matrix[m(1,3)]) | (symb & matrix[m(1,4)])
				                    | (symb & matrix[m(0,1)]) | (symb & matrix[m(2,3)]) | (symb & matrix[m(2,4)])
				                    | (symb & matrix[m(6,4)]) | (symb & matrix[m(6,2)]) ) 
				    sft=!matrix[0]; else sft=matrix[0]; 
            //                sft=matrix[0]; 
			  end	
		3998: dl0<=!(sdelay>0);
		3999: begin
			qmatrix <={
			   //Row 7| , N / V X ALT CTRL sft
				(matrix[5*8+5] & !symb) |(matrix[m(2,3)] & symb & dl0), matrix[7*8+3], 
				(symb & matrix[m(0,4)] & !sft)|(matrix[m(0,3)] & symb & dl0) , matrix[m(0,4)] & !symb,
				matrix[m(0,2)] & !symb, matrix[0*8+5],
				 matrix[1*8+6] | BSkey | gb , sft | mbs | gbc, 
				//Row 6| U T 0 E Q 6 2 8
				matrix[m(5,3)] & !symb, matrix[2*8+4] & !symb,
				(matrix[m(4,0)] & !sft & !(mbs|gbc))|(matrix[m(4,1)] & sft & !(mbs|gbc)),matrix[2*8+2],
				matrix[2*8+0], (matrix[m(4,4)] & !sft & !(mbs|gbc))|(matrix[m(6,4)]& symb & dl0)
				,matrix[3*8+1] & ~exkeys, (matrix[m(4,2)] & !symb & !sft & !(mbs|gbc))|(matrix[m(7,4)] & symb & dl0),
				//Row 5| O Y - R TAB I W 9
				matrix[5*8+1],matrix[5*8+4] & !symb,
				(matrix[m(3,6)] & dl0)|(matrix[m(4,0)] & sft & !symb & !(mbs|gbc))| (matrix[m(6,3)] & symb), matrix[2*8+3] & !symb,
				matrix[2*8+5],matrix[5*8+2],
				matrix[2*8+1],(matrix[m(4,1)] & !sft  & !(mbs|gbc))|(matrix[m(4,2)] & sft & !symb  & !(mbs|gbc)),
				//Row 4| J D P A 1 H 3 L
				matrix[m(6,3)] & !symb,matrix[m(1,2)] & !symb,
				matrix[5*8+0],matrix[m(1,0)] & !symb,
				matrix[3*8+0] & ~exkeys, matrix[m(6,4)] & !symb,
				matrix[3*8+2] & ~exkeys, matrix[m(6,1)] & !symb,
				//Row 3| ; G = F S K CAPSLOCK [
				(matrix[4*8+5] & !symb) |(matrix[m(0,1)] & symb & dl0),matrix[m(1,4)] & !symb,
				(matrix[2*8+6] & !symb) | (matrix[m(6,1)] & symb) | (matrix[m(6,2)] & symb & dl0),matrix[m(1,3)] & !symb,
				matrix[m(1,1)] & !symb,matrix[m(6,2)] & !symb,
				matrix[1*8+5],(symb & matrix[m(5,4)] & !sft)|(matrix[m(1,3)] & symb & dl0),
				//Row 2| " M £ B C . Z ]
				(matrix[m(4,6)] & dl0 & !symb)|(matrix[m(4,3)] & sft)|(matrix[m(4,3)] & symb), matrix[7*8+2],
				(symb & matrix[m(0,2)] & !sft)|(matrix[m(1,0)] & symb & dl0), matrix[m(7,4)] & !symb, 
				matrix[m(0,3)] & !symb, (matrix[5*8+6] & !symb) |(matrix[m(2,4)] & symb & dl0),
				matrix[0*8+1] & !symb, (symb & matrix[m(5,3)]& !sft)|(matrix[m(1,4)] & symb & dl0),
				//Row 1| DOWN SPACE \ RIGHT ESC UP LEFT ENTER
				matrix[7*8+6] | js1[2], matrix[7*8+0] | js1[4], 
				(symb & matrix[m(1,2)] & !sft)|(matrix[m(1,1)] & symb & dl0), matrix[6*8+6] | js1[0], 
				matrix[3*8+5], matrix[0*8+6] | js1[3],
				matrix[7*8+5] | BSkey | js1[1], matrix[6*8+0],
				//Row 0| 7 4 F5 F3 F2 5 F1 F4
				(matrix[m(4,3)] & !sft & !symb & !(mbs|gbc))|(matrix[m(4,4)] & sft), matrix[3*8+3] & ~exkeys, 
				((mbs|gbc) & matrix[m(4,0)]) | ((mb|gb) & matrix[3*8+4]) | js0[4], ((mbs|gbc) & matrix[m(4,2)]) | ((mb|gb) & matrix[3*8+2]) | js0[0], 
				((mbs|gbc) & matrix[m(4,3)]) | ((mb|gb) & matrix[3*8+1]) | js0[2], matrix[3*8+4] & ~exkeys, 
				((mbs|gbc) & matrix[m(4,4)]) | ((mb|gb) & matrix[3*8+0]) | js0[1], ((mbs|gbc) & matrix[m(4,1)]) | ((mb|gb) & matrix[3*8+3]) | js0[3]
				};
			end
		4000: begin
			keyss[4]<=~matrix[6*8+0];
			keyss[0]<=~matrix[0*8+6];
			keyss[1]<=~matrix[7*8+6];
			keyss[2]<=~matrix[7*8+5];
			keyss[3]<=~matrix[6*8+6];
			end
		endcase
	end
end
	
endmodule
