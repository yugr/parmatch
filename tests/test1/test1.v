module MOD1 #(parameter A, parameter B) ();
endmodule

MOD1 inst1;
MOD1 #(.A(1)) inst2;
MOD1 #(.A(1), .B(1)) inst3;
MOD1 #(1) inst4;
MOD1 #(1, 2) inst5;

