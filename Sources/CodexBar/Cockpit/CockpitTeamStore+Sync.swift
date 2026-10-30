import CodexBarCore
import Foundation

extension CockpitTeamStore {
    func create(endpoint: String, spaceName: String, deviceName: String, bootstrapSecret: String) async {
        await self.enroll(endpoint: endpoint, deviceName: deviceName) { client, deviceID in
            try await client.createSpace(
                name: spaceName,
                displayName: deviceName,
                deviceID: deviceID,
                bootstrapSecret: bootstrapSecret)
        }
    }

    func join(endpoint: String, inviteCode: String, deviceName: String) async {
        await self.enroll(endpoint: endpoint, deviceName: deviceName) { client, deviceID in
            try await client.join(inviteCode: inviteCode, displayName: deviceName, deviceID: deviceID)
        }
    }

    private func enroll(
        endpoint: String,
        deviceName: String,
        action: (CockpitTeamClient, String) async throws -> CockpitTeamEnrollment) async
    {
        guard !self.isBusy, self.connection == nil, !self.hasPendingEnrollment, self.canSave else { return }
        self.isBusy = true
        self.errorMessage = nil
        let generation = self.generation
        defer { if self.generation == generation { self.isBusy = false } }
        do {
            let client = try self.clientFactory(endpoint)
            let deviceID = UUID().uuidString.lowercased()
            // Check local persistence before consuming a one-use invitation or creating an owner.
            try self.persistThrowing()
            try self.saveToken("pending-enrollment", client.endpoint, deviceID)
            try self.saveToken(nil, client.endpoint, deviceID)
            let result = try await action(client, deviceID)
            self.pendingEnrollment = PendingEnrollment(
                endpoint: client.endpoint,
                deviceID: deviceID,
                deviceName: deviceName,
                result: result)
            self.hasPendingEnrollment = true
            guard self.generation == generation, !Task.isCancelled else { return }
            try await self.finishEnrollment(generation: generation)
        } catch { if self.generation == generation { self.show(error) } }
    }

    func retryEnrollment() async {
        guard !self.isBusy, self.hasPendingEnrollment else { return }
        self.isBusy = true
        self.errorMessage = nil
        let generation = self.generation
        defer { if self.generation == generation { self.isBusy = false } }
        do {
            try await self.finishEnrollment(generation: generation)
        } catch {
            if self.generation == generation { self.show(error) }
        }
    }

    private func finishEnrollment(generation: UUID) async throws {
        guard let pending = self.pendingEnrollment else { return }
        let client = try self.clientFactory(pending.endpoint)
        try self.saveToken(pending.result.token, pending.endpoint, pending.deviceID)
        self.connection = Connection(
            endpoint: pending.endpoint,
            spaceID: pending.result.spaceID,
            spaceName: pending.result.spaceID,
            deviceID: pending.deviceID,
            deviceName: pending.deviceName,
            role: pending.result.inviteCode == nil ? .member : .owner)
        try self.persistThrowing()
        self.inviteCode = pending.result.inviteCode
        self.inviteExpiresAt = pending.result.inviteExpiresAt.map(Date.init(timeIntervalSince1970:))
        self.pendingEnrollment = nil
        self.hasPendingEnrollment = false
        let identity = try await client.me(token: pending.result.token)
        guard self.generation == generation, !Task.isCancelled else { return }
        try self.apply(identity)
        try await self.initializeSettings(client: client, token: pending.result.token, generation: generation)
        self.persist()
    }

    func refresh() async {
        self.reconcileAccount()
        await self.withSession { client, token, generation in
            let identity = try await client.me(token: token)
            guard self.generation == generation, !Task.isCancelled else { return }
            try self.apply(identity)
            try await self.initializeSettings(client: client, token: token, generation: generation)
            guard self.generation == generation, let connection = self.connection, !Task.isCancelled else { return }
            let date = self.now()
            let shouldUpload = self.lastUploadAt.map { date.timeIntervalSince($0) >= 300 } ?? true
            let remote: [CockpitTeamDeviceSnapshot]
            if shouldUpload {
                var effectiveConnection = connection
                effectiveConnection.shareUsage = connection.shareUsage && self.accountMatches
                var (snapshot, status) = self.usageSnapshot(effectiveConnection, date)
                snapshot.timestamp = max(snapshot.timestamp, (self.lastUploadTimestamp ?? 0) + 1)
                self.lastUploadTimestamp = snapshot.timestamp
                self.persist()
                self.uploadStatus = connection.shareUsage && !self.accountMatches
                    ? L("Account changed or quota is stale. Usage sharing is paused.") : status
                remote = try await client.sync(
                    snapshot,
                    settingsRevision: self.sharedSettings.revision,
                    appVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
                        ?? "development",
                    token: token)
            } else {
                remote = try await client.snapshots(token: token)
            }
            guard self.generation == generation, !Task.isCancelled else { return }
            let active = Set(identity.members.map(\.deviceID))
            self.snapshots = remote.filter { active.contains($0.deviceID) }
            if shouldUpload { self.lastUploadAt = date }
            self.lastSyncedAt = date
            self.persist()
            if let basis = self.basis {
                let plan = try await client.dailyPlan(basis: basis, initialRisk: 0, change: nil, token: token)
                guard self.generation == generation, !Task.isCancelled else { return }
                self.plan = plan
                self.persist()
            } else {
                self.plan = nil
                self.persist()
            }
        }
    }

    func saveGroups(_ groups: CockpitTeamGroups, expectedRevision: Int) async {
        await self.withSession { client, token, generation in
            do {
                let settings = try await client.saveGroups(groups, expectedRevision: expectedRevision, token: token)
                guard self.generation == generation, !Task.isCancelled else { return }
                self.sharedSettings = settings
                self.persist()
            } catch CockpitTeamError.conflict {
                let settings = try await client.settings(token: token)
                guard self.generation == generation, !Task.isCancelled else { return }
                self.sharedSettings = settings
                self.persist()
                throw CockpitTeamError.conflict
            }
        }
    }

    func invite() async {
        guard self.connection?.role == .owner else { return }
        await self.withSession { client, token, generation in
            let invite = try await client.invite(maxUses: 1, expiresHours: 24, token: token)
            guard self.generation == generation, !Task.isCancelled else { return }
            self.inviteCode = invite.inviteCode
            self.inviteExpiresAt = Date(timeIntervalSince1970: invite.inviteExpiresAt)
        }
    }

    func revoke(deviceID: String) async {
        guard self.connection?.role == .owner, deviceID != self.connection?.deviceID else { return }
        await self.withSession { client, token, generation in
            try await client.revoke(deviceID: deviceID, token: token)
            guard self.generation == generation, !Task.isCancelled else { return }
            self.identity?.members.removeAll { $0.deviceID == deviceID }
            self.snapshots.removeAll { $0.deviceID == deviceID }
            self.persist()
        }
    }

    func setPersonalBudget(_ value: Double?, expectedPlan: CockpitTeamDailyPlan) async {
        guard let basis = self.checkedBasis(for: expectedPlan) else { return }
        guard let person = self.currentPerson else { return }
        await self.changePlan(CockpitTeamPlanChange(
            kind: .person,
            personID: person.id,
            value: value,
            expectedRevision: expectedPlan.people[person.id]?.revision ?? 0), basis: basis)
    }

    func setRisk(_ value: Double?, expectedPlan: CockpitTeamDailyPlan) async {
        guard let basis = self.checkedBasis(for: expectedPlan) else { return }
        await self.changePlan(CockpitTeamPlanChange(
            kind: .risk,
            value: value,
            expectedRevision: expectedPlan.risk.revision), basis: basis)
    }

    private func checkedBasis(for expectedPlan: CockpitTeamDailyPlan) -> CockpitTeamPlanBasis? {
        guard expectedPlan == self.currentPlan, let basis = self.basis,
              expectedPlan.basis.localDate == basis.localDate,
              Self.date(expectedPlan.basis.resetsAt) == Self.date(basis.resetsAt)
        else { self.show(CockpitTeamError.conflict); return nil }
        return basis
    }

    private func changePlan(_ change: CockpitTeamPlanChange, basis: CockpitTeamPlanBasis) async {
        await self.withSession { client, token, generation in
            do {
                let plan = try await client.dailyPlan(basis: basis, initialRisk: 0, change: change, token: token)
                guard self.generation == generation, !Task.isCancelled else { return }
                self.plan = plan
                self.persist()
            } catch CockpitTeamError.conflict {
                let plan = try await client.dailyPlan(basis: basis, initialRisk: 0, change: nil, token: token)
                guard self.generation == generation, !Task.isCancelled else { return }
                self.plan = plan
                self.persist()
                throw CockpitTeamError.conflict
            }
        }
    }

    private func initializeSettings(client: CockpitTeamClient, token: String, generation: UUID) async throws {
        guard self.sharedSettings.value == nil, let connection = self.connection,
              connection.role == .owner else { return }
        let person = CockpitTeamPerson(
            id: UUID().uuidString.lowercased(),
            name: L("Me"),
            deviceIDs: [connection.deviceID])
        let value = CockpitTeamSettingsValue(groups: CockpitTeamGroups(groups: [person]), pricing: .bundled)
        let settings = try await client.saveSettings(
            value,
            expectedRevision: self.sharedSettings.revision,
            token: token)
        guard self.generation == generation, !Task.isCancelled else { return }
        self.sharedSettings = settings
        self.persist()
    }

    private func apply(_ identity: CockpitTeamIdentity) throws {
        guard identity.space.id == self.connection?.spaceID, identity.deviceID == self.connection?.deviceID else {
            throw CockpitTeamError.invalidResponse
        }
        self.identity = identity
        if identity.sharedSettings.revision >= self.sharedSettings.revision {
            self.sharedSettings = identity.sharedSettings
        }
        self.connection?.spaceName = identity.space.name
        self.connection?.role = identity.role
    }

    private func withSession(_ action: (CockpitTeamClient, String, UUID) async throws -> Void) async {
        guard !self.isBusy, !self.hasPendingEnrollment, self.canSave, let connection, connection.enabled else { return }
        let generation = self.generation
        self.isBusy = true
        self.errorMessage = nil
        defer { if self.generation == generation { self.isBusy = false } }
        do {
            guard let token = try self.loadToken(connection.endpoint, connection.deviceID) else {
                throw CockpitTeamCredentialError.unavailable
            }
            let client = try self.clientFactory(connection.endpoint)
            try await action(client, token, generation)
        } catch {
            if self.generation == generation, !Task.isCancelled { self.show(error) }
        }
    }

    private func show(_ error: any Error) {
        switch error {
        case CockpitTeamError.conflict:
            self.errorMessage = L("Someone else changed this data. Review the latest version and save again.")
        case CockpitTeamError.invalidEndpoint:
            self.errorMessage = L("Enter an HTTPS server address without a path, query or credentials.")
        case CockpitTeamError.accessDenied:
            self.errorMessage = L("Access was denied. Check the invitation, server key or device access.")
        case CockpitTeamError.rateLimited:
            self.errorMessage = L("Too many requests. Wait a minute before trying again.")
        case CockpitTeamCredentialError.unavailable:
            self.errorMessage = L("The team credential is unavailable in Keychain. Unlock this Mac and try again.")
        case CockpitTeamError.invalidRequest:
            self.errorMessage = L("Check the names, device assignments and budget values.")
        default:
            self.errorMessage = L("Team sync failed. Last known data is retained; try again when connected.")
        }
    }
}
