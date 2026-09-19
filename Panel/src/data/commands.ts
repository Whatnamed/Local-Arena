import raw from "./commands.txt?raw";

/**
 * Full Commands.txt text, bundled (the Commands page reads this, not disk).
 *
 * The "ADD TEAMS" and "COORDINATED BUY" regions are Bot-only and are no longer
 * parsed: the Cosmetics-only Panel shows just the shared command list.
 */
export const COMMANDS_TXT: string = raw;
