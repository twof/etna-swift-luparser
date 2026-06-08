// Harvested witnesses: each is a counterexample for (mutant, property)
// produced by fuzzing that mutant (scripts/detect.sh). Each must be a
// real, parsable input that round-trips `true` on the CLEAN build — see
// WitnessTests (guards against discard-only non-witnesses).
struct Witness { let mutant: String; let kind: String; let wire: String }
let harvestedWitnesses: [Witness] = [
    Witness(mutant: "wsP_1", kind: "val", wire: "(IntVal 0)"),
    Witness(mutant: "wsP_1", kind: "exp", wire: "(Op1 Not (Val (BoolVal true)))"),
    Witness(mutant: "wsP_1", kind: "stat", wire: "(If (Val (BoolVal true)) (Block ((Empty))) (Block ((Empty))))"),
    Witness(mutant: "stringP_1", kind: "exp", wire: "(Op2 (Val (StringVal #R29qcw==)) Gt (Op2 (Var (Name (VarName #X3g=))) Concat (Var (Name (VarName #X3g=)))))"),
    Witness(mutant: "stringP_1", kind: "stat", wire: "(Assign (Proj (Op2 (Var (Name (VarName #eA==))) Minus (Var (Name (VarName #X3g=)))) (TableConst ((FieldKey (Val (IntVal -511)) (Val (StringVal #ezNMajh2)))))) (Op2 (Var (Name (VarName #eQ==))) Divide (Val (IntVal -491))))"),
    Witness(mutant: "boolValP_1", kind: "exp", wire: "(Op2 (Op2 (Op2 (Val (BoolVal false)) Plus (Var (Proj (Val (IntVal 428)) (Val (BoolVal true))))) Eq (Val (IntVal -680))) Ge (Op2 (Op1 Neg (Op2 (Var (Name (VarName #X0c=))) Times (Var (Name (VarName #X0c=))))) Minus (TableConst ((FieldName (VarName #eA==) (Val (NilVal))) (FieldKey (Var (Name (VarName #X0c=))) (Val (NilVal)))))))"),
    Witness(mutant: "boolValP_1", kind: "stat", wire: "(If (Val (BoolVal true)) (Block ((Empty))) (Block ((Empty))))"),
    Witness(mutant: "stringValP_1", kind: "val", wire: "(StringVal #)"),
    Witness(mutant: "stringValP_1", kind: "exp", wire: "(Val (StringVal #))"),
    Witness(mutant: "stringValP_1", kind: "stat", wire: "(Repeat (Block ((Empty))) (Val (StringVal #)))"),
    Witness(mutant: "stringValP_2", kind: "val", wire: "(StringVal #)"),
    Witness(mutant: "stringValP_2", kind: "exp", wire: "(Val (StringVal #))"),
    Witness(mutant: "stringValP_2", kind: "stat", wire: "(Repeat (Block ((Empty))) (Val (StringVal #)))"),
    Witness(mutant: "stringValP_3", kind: "exp", wire: "(Op1 Not (Val (BoolVal true)))"),
    Witness(mutant: "stringValP_3", kind: "stat", wire: "(Assign (Name (VarName #eDA=)) (Op1 Not (Val (BoolVal false))))"),
    Witness(mutant: "stringValP_4", kind: "val", wire: "(StringVal #)"),
    Witness(mutant: "stringValP_4", kind: "exp", wire: "(Val (StringVal #))"),
    Witness(mutant: "stringValP_4", kind: "stat", wire: "(Repeat (Block ((Empty))) (Val (StringVal #)))"),
    Witness(mutant: "bofP_1", kind: "exp", wire: "(Op2 (Val (IntVal 1)) Ge (Val (IntVal 2)))"),
    Witness(mutant: "bofP_1", kind: "stat", wire: "(Assign (Name (VarName #eA==)) (Op2 (Val (IntVal 1)) Ge (Val (IntVal 2))))"),
    Witness(mutant: "nameP_2", kind: "exp", wire: "(Var (Name (VarName #eDA=)))"),
    Witness(mutant: "nameP_2", kind: "stat", wire: "(Assign (Name (VarName #eDA=)) (Op1 Not (Val (BoolVal false))))"),
    Witness(mutant: "statementP_1", kind: "stat", wire: "(If (Op1 Neg (Op1 Len (Op1 Neg (Val (NilVal))))) (Block ((Empty))) (Block ((If (Val (StringVal #TSM2RHg=)) (Block ((Assign (Name (VarName #WA==)) (Var (Name (VarName #eHk=)))))) (Block ())) (Assign (Name (VarName #WA==)) (Var (Name (VarName #Xw==)))))))"),
    Witness(mutant: "ppNot_1", kind: "exp", wire: "(Op1 Not (Val (BoolVal true)))"),
    Witness(mutant: "ppNot_1", kind: "stat", wire: "(Assign (Name (VarName #eDA=)) (Op1 Not (Val (BoolVal false))))"),
]
