{
  description = "Build tools for json2dir in F*";
  inputs.nixpkgs.url = "https://flakehub.com/f/DeterminateSystems/nixpkgs-weekly/0.1";
  outputs = { nixpkgs, ... }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      tools = system:
        let
          pkgs = import nixpkgs { inherit system; };
          p = pkgs.ocaml-ng.ocamlPackages_5_3.overrideScope (self: prev: {
            ocaml = prev.ocaml.overrideAttrs (_: { doCheck = false; });
          });
        in pkgs.symlinkJoin {
          name = "json2dir-fstar-build-tools";
          paths = pkgs.lib.closePropagation
            (map (x: x.overrideAttrs (_: { doCheck = false; checkInputs = []; }))
              (with p; [ ocaml findlib batteries stdint zarith ppx_deriving ppx_deriving_yojson ]));
        };
    in {
      packages = eachSystem (system: { toolchain = tools system; });
      devShells = eachSystem (system:
        let pkgs = import nixpkgs { inherit system; }; in {
          default = pkgs.mkShell {
            packages = [ (tools system) pkgs.python3 ];
            OCAMLPATH = "${tools system}/lib/ocaml/5.3.0/site-lib";
          };
        });
    };
}
