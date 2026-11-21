/-
ListDecls.lean: list every constant defined in the project's own modules.

Run from the project root, after the project is built:
  lake env lean --run ListDecls.lean > all_decls.tsv

Output: one line per constant, "kind<TAB>name<TAB>module". Names are written with the
same raw dotted form as analysis/export_decls.py, so the two lists can be compared directly.
It imports the oleans only; nothing is re-elaborated.
-/
import Lean
open Lean

/-- Top-level module components that belong to the project (from lakefile.toml). -/
def projectRoots : List String :=
  ["BuildAid", "CompanionTheory", "Development", "Formalism", "GroundTheory", "Lemmata",
   "PositivityTheory", "ReciprocityTheory", "Supplements", "Main", "Statements"]

/-- Dotted name with no escaping, matching export_decls.py. -/
def rawName : Name → String
  | .anonymous => ""
  | .str .anonymous s => s
  | .num .anonymous n => toString n
  | .str p s => rawName p ++ "." ++ s
  | .num p n => rawName p ++ "." ++ toString n

def kindOf : ConstantInfo → String
  | .axiomInfo _ => "axiom"
  | .defnInfo _ => "def"
  | .thmInfo _ => "thm"
  | .opaqueInfo _ => "opaque"
  | .quotInfo _ => "quot"
  | .inductInfo _ => "ind"
  | .ctorInfo _ => "ctor"
  | .recInfo _ => "rec"

def isProjectModule (m : Name) : Bool :=
  projectRoots.contains (rawName m.getRoot)

def main (args : List String) : IO UInt32 := do
  let roots := if args.isEmpty then [`Main, `Statements] else args.map String.toName
  initSearchPath (← findSysroot)
  let env ← importModules (roots.toArray.map fun m => { module := m }) {} (trustLevel := 1024)
  let out ← IO.getStdout
  let mut nMods := 0
  let mut nConsts := 0
  for modName in env.header.moduleNames, md in env.header.moduleData do
    unless isProjectModule modName do continue
    nMods := nMods + 1
    let m := rawName modName
    if md.constants.isEmpty then
      out.putStrLn s!"none\t-\t{m}"
    for ci in md.constants do
      out.putStrLn s!"{kindOf ci}\t{rawName ci.name}\t{m}"
      nConsts := nConsts + 1
  IO.eprintln s!"project modules: {nMods}, constants: {nConsts}, all imported modules: {env.header.moduleNames.size}"
  return 0
