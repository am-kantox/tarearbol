locals_without_parens = Enum.flat_map(0..9, &[defsynch: &1, defasynch: &1])

[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: locals_without_parens,
  export: [locals_without_parens: locals_without_parens]
]
