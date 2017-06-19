import Foundation

public protocol SessionsHolder: class {
    var `default`: Session { get }
    var all: [Session] { get }
    func make(config: SessionConfig) -> Session
    func destroy(session: Session) throws
    func markAsDefault(session: Session) throws
}

extension SessionsHolder {
    
    func make() -> Session {
        return make(config: .default)
    }
}

public final class SessionsHolderImpl: SessionsHolder {
    
    private let sessionMaker: SessionMaker
    private let sessionsStorage: SessionsStorage
    private var sessions = NSHashTable<AnyObject>(options: .strongMemory)
    private var canKillDefaultSessions = false
    
    lazy public var `default`: Session = {
        return self.make()
    }()
    
    public var all: [Session] {
        return sessions.allObjects.flatMap { $0 as? Session }
    }
    
    init(
        sessionMaker: SessionMaker,
        sessionsStorage: SessionsStorage
        ) {
        self.sessionMaker = sessionMaker
        self.sessionsStorage = sessionsStorage
        
        try? restoreFromStorage()
    }
    
    private func restoreFromStorage() throws {
        let decodedSessions = try sessionsStorage.restore()
            .filter { !$0.id.isEmpty }
        
        decodedSessions
            .map { sessionMaker.session(id: $0.id, config: $0.config ) }
            .forEach { sessions.add($0) }
        
        if let defaultSession = decodedSessions
            .first(where: { $0.isDefault })
            .map({ sessionMaker.session(id: $0.id, config: $0.config ) }) {
            `default` = defaultSession
        }
    }
    
    public func make(config: SessionConfig) -> Session {
        let session = sessionMaker.session(id: .random(20), config: config)
        session.config = config
        
        sessions.add(session)
        return session
    }
    
    public func destroy(session: Session) throws {
        if !canKillDefaultSessions && session == `default` {
            throw SessionError.cantDestroyDefaultSession
        }
        
        if session.state == .destroyed {
            throw SessionError.sessionDestroyed
        }
        
        (session as? DestroyableSession)?.destroy()
        sessions.remove(session)
    }
    
    public func markAsDefault(session: Session) throws {
        if session.state == .destroyed {
            throw SessionError.sessionDestroyed
        }
        
        self.default = session
    }
    
    deinit {
        canKillDefaultSessions = true
        sessions.allObjects.flatMap { $0 as? Session } .forEach { try? destroy(session: $0) }
    }
}