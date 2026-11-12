import Foundation

/// A small reader for statecharts written as JSON (Charts/*.json), the same as the
/// website's statechart.js: nested states with an initial child, entry actions, and
/// per event a transition (or a list tried in order) with an optional target, guard
/// and actions. Guards and actions are named in the chart and written by the caller
/// (owner decision 12 Nov 2026, D-lite: docs/decisions/0021).
struct Statechart: Decodable {
    struct Transition: Decodable {
        /// A sibling state, ".child" for a child, or none: the state stays.
        let target: String?
        let guardName: String?
        let actions: [String]

        private enum CodingKeys: String, CodingKey { case target, guardName = "guard", actions }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            target = try c.decodeIfPresent(String.self, forKey: .target)
            guardName = try c.decodeIfPresent(String.self, forKey: .guardName)
            actions = try c.decodeIfPresent([String].self, forKey: .actions) ?? []
        }
    }

    /// One transition or a list of them, tried in order.
    private struct Transitions: Decodable {
        let list: [Transition]
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            list = (try? c.decode([Transition].self)) ?? [try c.decode(Transition.self)]
        }
    }

    struct Node: Decodable {
        let initial: String?
        let entry: [String]
        let on: [String: [Transition]]
        let states: [String: Node]

        private enum CodingKeys: String, CodingKey { case initial, entry, on, states }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            initial = try c.decodeIfPresent(String.self, forKey: .initial)
            entry = try c.decodeIfPresent([String].self, forKey: .entry) ?? []
            on = try (c.decodeIfPresent([String: Transitions].self, forKey: .on) ?? [:]).mapValues(\.list)
            states = try c.decodeIfPresent([String: Node].self, forKey: .states) ?? [:]
        }
    }

    /// The new state and the actions to run in order: the transition's, then the
    /// entry actions of the states it enters.
    struct Step: Equatable {
        let state: [String]
        let actions: [String]
    }

    let id: String
    let root: Node

    private enum CodingKeys: String, CodingKey { case id }

    init(from decoder: Decoder) throws {
        id = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
        root = try Node(from: decoder)
    }

    /// The chart `name`.json from the app's bundle.
    static func load(_ name: String, bundle: Bundle = .main) -> Statechart {
        guard let url = bundle.url(forResource: name, withExtension: "json"),
              let chart = try? JSONDecoder().decode(Statechart.self, from: Data(contentsOf: url))
        else { preconditionFailure("The statechart \(name).json is missing from the app or cannot be read") }
        return chart
    }

    func node(_ path: [String]) -> Node? {
        path.reduce(Optional(root)) { node, name in node?.states[name] }
    }

    /// The path and the deepest initial child below it.
    private func settle(_ path: [String]) -> [String] {
        var out = path
        while let node = node(out), let first = node.initial { out.append(first) }
        return out
    }

    var initial: [String] { settle([]) }

    /// The state a transition on the state at `from` leads to, or nil when there is none of that name.
    func resolve(_ target: String, from: [String]) -> [String]? {
        let path = target.hasPrefix(".") ? from + [String(target.dropFirst())] : Array(from.dropLast()) + [target]
        return node(path) == nil ? nil : settle(path)
    }

    /// What `event` does in `state`, or nil when no state on the path takes it. The
    /// deepest state goes first; one whose guards all say no passes the event to its
    /// parent, as in SCXML.
    func transition(from state: [String], on event: String, allowed: (String) -> Bool) -> Step? {
        for depth in stride(from: state.count, through: 0, by: -1) {
            let path = Array(state.prefix(depth))
            guard let list = node(path)?.on[event],
                  let found = list.first(where: { $0.guardName.map(allowed) ?? true })
            else { continue }
            guard let target = found.target else { return Step(state: state, actions: found.actions) }
            guard let next = resolve(target, from: path) else {
                preconditionFailure("\(id): no state \(target) from \(path.joined(separator: "."))")
            }
            // The states the old and new paths share are not entered again.
            let same = zip(state, next).prefix { $0.0 == $0.1 }.count
            let entered = ((same + 1)..<(next.count + 1)).flatMap { node(Array(next.prefix($0)))?.entry ?? [] }
            return Step(state: next, actions: found.actions + entered)
        }
        return nil
    }

    /// Every state's path, with the transitions written on it, for the tests.
    var paths: [(path: [String], node: Node)] {
        var out: [(path: [String], node: Node)] = []
        func walk(_ node: Node, _ path: [String]) {
            out.append((path, node))
            for (name, child) in node.states { walk(child, path + [name]) }
        }
        walk(root, [])
        return out
    }

    /// Every guard and every action the chart names.
    var guardNames: Set<String> { Set(paths.flatMap { $0.node.on.values.flatMap { $0.compactMap(\.guardName) } }) }
    var actionNames: Set<String> {
        Set(paths.flatMap { $0.node.entry + $0.node.on.values.flatMap { $0.flatMap(\.actions) } })
    }
}
