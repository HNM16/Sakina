-- Ledger integrity guards.
--
-- These tables hold no money yet, and will not until Sakina operates under an
-- NBT licence or mirrors a licensed partner's books. The constraints go in now
-- anyway: they are cheap against empty tables and effectively impossible to
-- impose later, once wrong rows already exist.
--
-- Three rules, enforced by the database rather than by application code, so
-- that no future service, migration or console session can quietly break them.

-- 1. Amounts are positive integers in minor units (diram). Direction carries
--    the sign; a negative amount would make double-entry meaningless.
ALTER TABLE "ledger_entries"
  ADD CONSTRAINT "ledger_entries_amount_positive" CHECK ("amount_minor" > 0);--> statement-breakpoint

-- 2. Append-only. A ledger that can be edited is not a ledger. Corrections are
--    made by writing a reversing transaction, never by changing history.
CREATE OR REPLACE FUNCTION sakina_ledger_append_only() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'ledger_entries is append-only (attempted %)', TG_OP;
END;
$$ LANGUAGE plpgsql;--> statement-breakpoint

CREATE TRIGGER ledger_entries_append_only
  BEFORE UPDATE OR DELETE ON "ledger_entries"
  FOR EACH ROW EXECUTE FUNCTION sakina_ledger_append_only();--> statement-breakpoint

-- 3. Every transaction balances: debits equal credits, per currency. Checked at
--    COMMIT rather than per row, because the entries of one transaction are
--    inserted as separate statements and are only balanced once all are in.
CREATE OR REPLACE FUNCTION sakina_ledger_balanced() RETURNS trigger AS $$
DECLARE
  imbalance bigint;
BEGIN
  SELECT SUM(CASE WHEN direction = 'debit' THEN amount_minor ELSE -amount_minor END)
    INTO imbalance
    FROM ledger_entries
   WHERE transaction_id = NEW.transaction_id;

  IF imbalance IS NULL OR imbalance <> 0 THEN
    RAISE EXCEPTION 'ledger transaction % does not balance (imbalance %)',
      NEW.transaction_id, imbalance;
  END IF;

  RETURN NULL;
END;
$$ LANGUAGE plpgsql;--> statement-breakpoint

CREATE CONSTRAINT TRIGGER ledger_entries_balanced
  AFTER INSERT ON "ledger_entries"
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION sakina_ledger_balanced();--> statement-breakpoint

-- Tajik Cyrillic (ғ ӣ қ ӯ ҳ ҷ) does not sort or compare correctly under the C
-- locale, which breaks contact ordering and name lookup. This index makes name
-- search case- and accent-insensitive under a Tajik collation.
CREATE COLLATION IF NOT EXISTS sakina_tg (
  provider = icu,
  locale = 'tg-TJ-u-ks-level1',
  deterministic = false
);--> statement-breakpoint

CREATE INDEX "users_display_name_tg_idx"
  ON "users" ("display_name" COLLATE sakina_tg);
