module M #(parameter integer A, parameter B, parameter real C) ();
endmodule

M #(.A(1), .B(1), .C(1)) m1;
M #(.B(1), .C(1)) m2;
M #(.A(1), .C(1)) m2;

