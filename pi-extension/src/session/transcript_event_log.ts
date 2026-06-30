import type { TranscriptEvent } from "./transcript_event.js";

/**
 * Process-local, append-only transcript event store.
 *
 * The Pi SDK is the durable session owner; this log is the extension's typed
 * in-memory mirror used to answer Remote Pi `session_sync` without keeping the
 * old SDK-message-shaped buffer as projection state.
 */
export class TranscriptEventLog {
  private readonly events: TranscriptEvent[] = [];
  private readonly seen = new Set<string>();

  append(event: TranscriptEvent): boolean {
    if (this.seen.has(event.eventId)) return false;
    this.seen.add(event.eventId);
    this.events.push(event);
    return true;
  }

  appendAll(events: readonly TranscriptEvent[]): number {
    let appended = 0;
    for (const event of events) {
      if (this.append(event)) appended++;
    }
    return appended;
  }

  replace(events: readonly TranscriptEvent[]): void {
    this.clear();
    this.appendAll(events);
  }

  clear(): void {
    this.events.length = 0;
    this.seen.clear();
  }

  forSession(sessionId: string): readonly TranscriptEvent[] {
    return this.events.filter((event) => event.sessionId === sessionId);
  }

  entries(): readonly TranscriptEvent[] {
    return [...this.events];
  }
}
