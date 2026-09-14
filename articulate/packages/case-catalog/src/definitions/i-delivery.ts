import type { CaseFactDefinition } from '../types.ts';
import { section, yes } from './_helpers.ts';

const d = section('I', 'delivery');

/** Section I — getting it back to the practice, which is what most calls are about. */
export const deliveryFacts: CaseFactDefinition[] = [
  d('delivery.ship_date', 'Shipped', 'datetime', 10,
    ['has it shipped', 'when did it go out', 'when did you send it'],
    { necessity: 'required', safety: 'commercial', isDhr: true }),
  d('delivery.carrier', 'Carrier', 'text', 8,
    ['who is it with', 'which courier', 'how is it coming'],
    { necessity: 'required', safety: 'commercial' }),
  d('delivery.tracking_number', 'Tracking number', 'text', 9,
    ['what is the tracking number', 'can i track it', 'do you have a tracking'],
    { necessity: 'required', safety: 'commercial' }),
  d('delivery.expected_arrival', 'Expected arrival', 'date', 10,
    ['when will it get here', 'will it arrive before the appointment',
     'will it be here tomorrow'],
    { necessity: 'required', safety: 'commercial' }),
  d('delivery.delivered_at', 'Delivered', 'datetime', 9,
    ['has it arrived', 'was it delivered', 'did you deliver it'],
    { necessity: 'expected', safety: 'commercial' }),
  d('delivery.received_by', 'Received by', 'text', 5,
    ['who signed for it'],
    { necessity: 'optional', safety: 'commercial' }),
  d('delivery.contents', 'What is in the box', 'text', 8,
    ['what did you send', 'what is in the package', 'did you send the model back'],
    { necessity: 'required', safety: 'informational' }),
  d('delivery.models_returned', 'Models returned', 'boolean', 5,
    ['did you send the models back'],
    { necessity: 'expected', safety: 'informational' }),
  d('delivery.instructions_enclosed', 'Handling instructions enclosed', 'boolean', 7,
    ['did you include instructions', 'are there cementation instructions in the box'],
    { necessity: 'required', safety: 'patient_safety' }),
  d('delivery.pickup_scheduled', 'Pickup scheduled', 'datetime', 6,
    ['when is the driver coming', 'is the route picking up today'],
    { necessity: 'optional', safety: 'commercial' }),
  d('delivery.delay_reason', 'Delay reason', 'text', 10,
    ['why is it late', 'why has it not shipped', 'what happened to my case'],
    { appliesWhen: yes('is_delayed'), necessity: 'blocking', safety: 'commercial',
      helpText: 'A late case with no stated reason is how a practice decides to ' +
                'try a different lab. The reason is a first-class fact.' }),
  d('delivery.revised_due_date', 'Revised due date', 'date', 10,
    ['what is the new date', 'when will it be ready now'],
    { appliesWhen: yes('is_delayed'), necessity: 'blocking', safety: 'commercial' }),
];
