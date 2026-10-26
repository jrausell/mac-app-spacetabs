import AppKit
import SpaceTabsCore

extension AppModel {
    func activeSpaceChanged() {
        guard !terminating else { return }
        desktopRevision += 1
        spaceChangeCount += 1
        lastSpaceChange =
            L10n.tr("\(Date.now.formatted(date: .omitted, time: .standard)) · waiting for the transition to finish")
        noteUserInteraction()
        reflowTask?.cancel()
        // Let an already-started placement finish its transaction; cancelling
        // it during the animation could require an unnecessary AX rollback.
        spaceChangeTask?.cancel()
        spaceTransitioning = true
        layoutChanged()
        let revision = desktopRevision
        spaceChangeTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, !terminating, desktopRevision == revision else { return }
            spaceChangeTask = nil
            spaceTransitioning = displayProfileTask != nil
            lastSpaceChange =
                L10n.tr(
                    "\(Date.now.formatted(date: .omitted, time: .standard)) · transition finished without a permanent pause"
                )
            lastVisibleFrame = nil
            // A Space notification is not an instruction to move, focus or
            // restore windows. Resume normal event-driven handling only.
            layoutChanged()
            if pendingAutomaticProfile != nil { applyAutomaticProfileIfReady() }
        }
    }

    func suspendForDesktopChange(_ reason: String) {
        displayProfileTask?.cancel()
        displayProfileTask = nil
        pendingAutomaticProfile = nil
        spaceChangeTask?.cancel()
        spaceChangeTask = nil
        spaceTransitioning = false
        desktopRevision += 1
        noteUserInteraction()
        paused = true
        reflowTask?.cancel()
        message = reason
        layoutChanged()
    }

    func togglePause() {
        if sendToManager(.pause) { return }
        if demo || originals.isEmpty {
            paused.toggle()
            layoutChanged()
            if !paused {
                restoreSavedSession(automatically: true)
                applyApplicationAssignments()
            }
            return
        }
        if paused {
            perform(allowPaused: true) {
                let revision = self.desktopRevision
                let frames = try self.managedFrames(tabs: self.tabs)
                try await self.windowManager.applyLayout(
                    frames: frames, selected: Zone.allCases.compactMap { self.tabs.selected[$0] })
                if self.desktopRevision == revision {
                    self.paused = false
                    self.message = nil
                }
            }
        } else {
            perform {
                self.paused = true
                self.layoutChanged()
                var errors: [String] = []
                for (id, original) in self.originals {
                    do { try await self.windowManager.restore(id, state: self.safeRestoration(original)) } catch {
                        errors.append(error.localizedDescription)
                    }
                }
                if !errors.isEmpty {
                    throw WindowError(
                        message: L10n.tr(
                            "Paused. Some windows could not be restored: \(errors.joined(separator: "; "))"))
                }
            }
        }
    }

    func prepareForTermination() async -> [String] {
        terminating = true
        tabSelectionRunner.cancel()
        await tabSelectionRunner.wait()
        appearanceSaveTask?.cancel()
        for task in assignedLaunchTasks.values { task.cancel() }
        assignedLaunchTasks.removeAll()
        reflowTask?.cancel()
        refreshTask?.cancel()
        refreshTask = nil
        await scanTask?.value
        await operationTask?.value
        var errors: [String] = []
        if !demo && !configurationBlocked {
            do { try checkpoint(tabs: tabs, originals: originals) } catch {
                errors.append(L10n.tr("Configuration: \(error.localizedDescription)"))
            }
        }
        for (id, original) in originals {
            do { try await windowManager.restore(id, state: safeRestoration(original)) } catch {
                errors.append("\(titles[id] ?? L10n.tr("Window")): \(error.localizedDescription)")
            }
        }
        return errors
    }
}
