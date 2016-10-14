module spram_32 #(parameter aw, dw) (x);
endmodule

   spram_32 #
     (
      .aw(10),
      .dw(dw)
      )
   dc_ram(.x(x));

   spram_32 #
     (
      .aw(10)
      )
   dc_ram(.x(x));

