dis86 {
  code_segments {
    main { seg "4000" name "main" }
  }

  structures {}

  functions {
    entry0 {
      start "0000:0000"
      end "0000:0157"
      mode "far"
      ret "None"
      args "0"
    }
    fcn_000418fe {
      start "4000:18fe"
      end "4000:19e1"
      mode "far"
      ret "u16"
      args "4"
    }
    fcn_0004d608 {
      start "4000:d608"
      end "4000:e1e3"
      mode "far"
      ret "None"
      args "4"
    }
    fcn_0004e1e3 {
      start "4000:e1e3"
      end "4000:e95d"
      mode "far"
      ret "None"
      args "4"
    }
    fcn_0004e95d {
      start "4000:e95d"
      end "4000:f1e3"
      mode "far"
      ret "None"
      args "None"
    }
  }

  globals {}
  text_section {}
}
