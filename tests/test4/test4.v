module M1 #(A, B) ();
endmodule

module M1 #(A, B) ();
endmodule

// This should trigger warning (m1 has compatible definitions)
M1 #(.A(1)) m1;

module M2 #(A, B) ();
endmodule

module M2 #(A) ();
endmodule

// This should not trigger warning (m1 has incompat. definitions)
M2 #(.A(1)) m2;

module M3 #(A, B) ();
endmodule

module M3 #(A, C) ();
endmodule

// Ditto
M3 #(.A(1)) m3;

