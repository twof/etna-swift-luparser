// A small applicative/alternative parser-combinator library — ported from
// alpaylan/etna-haskell-luparser `src/Parser.hs`.
//
//   newtype Parser a = P { doParse :: String -> Maybe (a, String) }
//
// We model the input as a `Substring` for cheap slicing. The combinators mirror
// the Haskell ones (Functor/Applicative/Alternative + get/eof/satisfy/char/
// string/int/chainl1/choice/between/sepBy); operators `<*>`, `*>`, `<*`, `<|>`
// keep the parser bodies in Lang.swift readable and close to the original.

public struct Parser<A> {
    public let doParse: (Substring) -> (A, Substring)?
    public init(_ doParse: @escaping (Substring) -> (A, Substring)?) { self.doParse = doParse }
}

// A `Parser` is an immutable value wrapping a pure parsing closure; the grammar
// is built once into `let` globals that capture only other (immutable) parsers,
// the immutable `reserved` set, and pure functions. It is therefore safe to
// share across the fuzzer's parallel engines.
extension Parser: @unchecked Sendable {}

// MARK: - Functor / Applicative

extension Parser {
    public func map<B>(_ f: @escaping (A) -> B) -> Parser<B> {
        Parser<B> { s in self.doParse(s).map { (f($0.0), $0.1) } }
    }
    /// Monadic bind — not in the Haskell Applicative interface, but a convenient
    /// way to express the same sequencing in Swift without currying gymnastics.
    public func flatMap<B>(_ f: @escaping (A) -> Parser<B>) -> Parser<B> {
        Parser<B> { s in self.doParse(s).flatMap { (a, r) in f(a).doParse(r) } }
    }
}

public func pure<A>(_ x: A) -> Parser<A> { Parser { (x, $0) } }

precedencegroup ParserApplicative { associativity: left higherThan: ParserAlternative }
precedencegroup ParserAlternative { associativity: left }

infix operator <*> : ParserApplicative
infix operator *>  : ParserApplicative
infix operator <*  : ParserApplicative
infix operator <|> : ParserAlternative

public func <*> <A, B>(pf: Parser<(A) -> B>, pa: Parser<A>) -> Parser<B> {
    pf.flatMap { f in pa.map(f) }
}
/// Sequence, keep the right result.
public func *> <A, B>(pa: Parser<A>, pb: Parser<B>) -> Parser<B> {
    pa.flatMap { _ in pb }
}
/// Sequence, keep the left result.
public func <* <A, B>(pa: Parser<A>, pb: Parser<B>) -> Parser<A> {
    pa.flatMap { a in pb.map { _ in a } }
}
/// Alternative: first parser, falling back to the second.
public func <|> <A>(p1: Parser<A>, p2: @autoclosure @escaping () -> Parser<A>) -> Parser<A> {
    Parser { s in p1.doParse(s) ?? p2().doParse(s) }
}

public func emptyP<A>() -> Parser<A> { Parser { _ in nil } }

// MARK: - Primitives

/// Next character, or failure at end of input.
public let get: Parser<Character> = Parser { s in
    guard let c = s.first else { return nil }
    return (c, s.dropFirst())
}

/// Succeeds only at end of input.
public let eof: Parser<Void> = Parser { s in s.isEmpty ? ((), s) : nil }

/// Keep a parse result only if it satisfies the predicate.
public func filterP<A>(_ f: @escaping (A) -> Bool, _ p: Parser<A>) -> Parser<A> {
    Parser { s in
        guard let (a, r) = p.doParse(s), f(a) else { return nil }
        return (a, r)
    }
}

public func satisfy(_ f: @escaping (Character) -> Bool) -> Parser<Character> { filterP(f, get) }

public let alpha: Parser<Character> = satisfy { $0.isLetter }
public let digit: Parser<Character> = satisfy { $0.isASCII && $0.isNumber }
public let upper: Parser<Character> = satisfy { $0.isUppercase }
public let lower: Parser<Character> = satisfy { $0.isLowercase }
public let spaceChar: Parser<Character> = satisfy { $0.isWhitespace }

public func char(_ c: Character) -> Parser<Character> { satisfy { $0 == c } }

/// Parse exactly the given string.
public func string(_ str: String) -> Parser<String> {
    Parser { s in
        var rest = s
        for c in str {
            guard rest.first == c else { return nil }
            rest = rest.dropFirst()
        }
        return (str, rest)
    }
}

/// A (possibly negative) integer literal.
public let int: Parser<Int> = Parser { s in
    let neg = string("-").doParse(s)
    let (sign, afterSign) = neg.map { ("-", $0.1) } ?? ("", s)
    guard let (ds, rest) = some(digit).doParse(afterSign) else { return nil }
    guard let n = Int(sign + String(ds)) else { return nil }
    return (n, rest)
}

// MARK: - Repetition (Alternative `some` / `many`)
//
// Implemented iteratively with a no-progress guard so a non-consuming parser
// (e.g. `pure []`) can't loop forever — the practical analog of Haskell's lazy
// `some`/`many`.

public func many<A>(_ p: Parser<A>) -> Parser<[A]> {
    Parser { s in
        var rest = s, acc: [A] = []
        while let (a, r) = p.doParse(rest), r.count < rest.count {
            acc.append(a); rest = r
        }
        return (acc, rest)
    }
}

public func some<A>(_ p: Parser<A>) -> Parser<[A]> {
    Parser { s in
        guard let (a0, r0) = p.doParse(s) else { return nil }
        var rest = r0, acc = [a0]
        while let (a, r) = p.doParse(rest), r.count < rest.count {
            acc.append(a); rest = r
        }
        return (acc, rest)
    }
}

// MARK: - Derived combinators

public func choice<A>(_ ps: [Parser<A>]) -> Parser<A> {
    Parser { s in
        for p in ps { if let r = p.doParse(s) { return r } }
        return nil
    }
}

public func between<O, A, C>(_ open: Parser<O>, _ p: Parser<A>, _ close: Parser<C>) -> Parser<A> {
    open *> p <* close
}

public func sepBy1<A, S>(_ p: Parser<A>, _ sep: Parser<S>) -> Parser<[A]> {
    p.flatMap { first in many(sep *> p).map { [first] + $0 } }
}

public func sepBy<A, S>(_ p: Parser<A>, _ sep: Parser<S>) -> Parser<[A]> {
    sepBy1(p, sep) <|> pure([])
}

/// One or more `p` separated by a left-associative binary operator `pop`.
public func chainl1<A>(_ p: Parser<A>, _ pop: Parser<(A, A) -> A>) -> Parser<A> {
    p.flatMap { first in
        many(pop.flatMap { op in p.map { y in (op, y) } }).map { ops in
            ops.reduce(first) { acc, pair in pair.0(acc, pair.1) }
        }
    }
}

// MARK: - Top-level entry

public enum ParseResult<A: Equatable>: Equatable {
    case ok(A)
    case err
}

/// `parse p s` — like Haskell's: succeed (ignoring leftover input) if `doParse`
/// yields a value, else fail.
public func parse<A: Equatable>(_ p: Parser<A>, _ s: String) -> ParseResult<A> {
    guard let (a, _) = p.doParse(Substring(s)) else { return .err }
    return .ok(a)
}
