/**
 * SMS delivery.
 *
 * Deliberately an interface with a stub implementation, because OTP delivery to
 * +992 is a procurement problem before it is a code problem:
 *
 *  - International aggregators (Twilio and friends) deliver to Tajik networks
 *    unreliably and at a price that does not survive contact with a free
 *    messenger's signup funnel.
 *  - The workable route is a direct arrangement with Tcell / Megafon Tajikistan
 *    / Babilon-M / ZET-Mobile, or a regional aggregator that already holds one.
 *  - Budget for flash-call verification as the primary path and SMS as the
 *    fallback: the user gets a dropped call and reads the last digits of the
 *    calling number. It is far cheaper per verification and already familiar
 *    across the region.
 *
 * Swap the implementation, keep the interface.
 */
export interface SmsProvider {
  readonly name: string;
  sendOtp(phone: string, code: string): Promise<void>;
}

/** Development only. The code is returned to the caller by the API instead of being sent. */
export class StubSmsProvider implements SmsProvider {
  readonly name = "stub";

  async sendOtp(phone: string, code: string): Promise<void> {
    console.log(`[sms:stub] would send code ${code} to ${phone}`);
  }
}
