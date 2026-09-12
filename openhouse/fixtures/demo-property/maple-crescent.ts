import { InMemoryStore } from '../../packages/truth-engine/src/store.ts';
import type { PropertyRecord } from '../../packages/truth-engine/src/store.ts';

export const DEMO_PROPERTY_ID = 'demo-maple-crescent';
export const DEMO_AGENT_ID = 'agent-sarah';

/**
 * 123 Maple Crescent — the demo property (§17).
 *
 * Seeded through the same claim → confirm path a real listing takes, not
 * written straight into resolved facts, so the demo exercises the verification
 * state machine rather than bypassing it. It carries deliberate imperfection:
 * a roof-year conflict between the MLS sheet and the seller disclosure, eight
 * facts marked unknown, a disclosed and remediated basement leak, and a
 * basement suite that is honestly not legal.
 */
export function buildDemoProperty(): InMemoryStore {
  const store = new InMemoryStore();

  const record: PropertyRecord = {
    property: {
      id: DEMO_PROPERTY_ID,
      slug: 'maple-crescent-123',
      status: 'published',
      addressLine1: '123 Maple Crescent',
      city: 'Calgary',
      province: 'AB',
      postalCode: 'T2Y 4X1',
      propertyType: 'detached',
      listPrice: 899900,
      bedrooms: 4,
      bathrooms: 3,
      livingAreaSqft: 2140,
      yearBuilt: 2019,
      agentName: 'Sarah Thompson',
      isDemo: true,
      applicability: {
        property_type: 'detached',
        has_garage: true,
        has_basement: true,
        has_basement_bathroom: true,
        has_suite: false,
        has_deck: true,
        has_fence: true,
        has_fireplace: true,
        has_wood_burning_appliance: false,
        has_ac: true,
        has_heat_pump: false,
        has_in_floor_heat: false,
        has_hrv: true,
        has_sump_pump: true,
        has_ensuite: true,
        has_kitchen_island: true,
        has_pool: false,
        has_hot_tub: false,
        has_solar: false,
        has_ev_charger: true,
        has_security_system: true,
        has_stucco: false,
        has_addition: false,
        has_crawlspace: false,
        is_tenanted: false,
        heating_type: 'forced_air_gas',
        water_source: 'municipal',
        has_septic: false,
        radon_tested: false,
      },
    },
    rooms: [
      room('room-entry',   'entry',   'Entry',            1, ['living_room', 'garage']),
      room('room-living',  'living_room', 'Living room',  2, ['entry', 'kitchen', 'dining']),
      room('room-kitchen', 'kitchen', 'Kitchen',          3, ['living_room', 'dining']),
      room('room-dining',  'dining',  'Dining room',      4, ['kitchen', 'living_room']),
      room('room-primary', 'primary_bedroom', 'Primary bedroom', 5, ['ensuite', 'upper_hall']),
      room('room-ensuite', 'ensuite', 'Ensuite',          6, ['primary_bedroom']),
      room('room-bed2',    'bedroom_2', 'Bedroom 2',      7, ['upper_hall']),
      room('room-bed3',    'bedroom_3', 'Bedroom 3',      8, ['upper_hall']),
      room('room-bonus',   'bonus_room', 'Bonus room',    9, ['upper_hall']),
      room('room-basement','basement', 'Basement',       10, ['utility', 'bedroom_4']),
      room('room-utility', 'utility', 'Utility room',    11, ['basement']),
      room('room-garage',  'garage',  'Garage',          12, ['entry']),
    ],
    claims: [],
    facts: [],
    commentary: [
      {
        id: 'comm-kitchen', scope: 'room', roomId: 'room-kitchen', topic: 'kitchen',
        author: 'agent', visibility: 'public', approved: true,
        text: 'The sellers renovated this kitchen in 2023 and cooked in it every ' +
              'day since — the island seats four and the pantry is deeper than it looks.',
      },
      {
        id: 'comm-yard', scope: 'property', roomId: null, topic: 'yard',
        author: 'agent', visibility: 'public', approved: true,
        text: 'The backyard faces south, so the deck holds sun from late morning ' +
              'until evening through the summer.',
      },
      {
        id: 'comm-seller', scope: 'property', roomId: null, topic: 'living',
        author: 'seller', visibility: 'public', approved: true,
        text: 'We raised two kids here. The bonus room started as a playroom and ' +
              'ended up as the place everyone watches hockey.',
      },
      {
        id: 'comm-private', scope: 'property', roomId: null, topic: 'motivation',
        author: 'agent', visibility: 'agent_only', approved: true,
        text: 'Sellers relocating for work in the spring; timing matters more to ' +
              'them than the last few thousand dollars.',
      },
    ],
    inclusions: [
      { kind: 'included', item: 'Refrigerator' },
      { kind: 'included', item: 'Gas range' },
      { kind: 'included', item: 'Dishwasher' },
      { kind: 'included', item: 'Over-range microwave' },
      { kind: 'included', item: 'Washer and dryer' },
      { kind: 'included', item: 'Window coverings' },
      { kind: 'included', item: 'Garage door opener and two remotes' },
      { kind: 'included', item: 'Level 2 EV charger' },
      { kind: 'excluded', item: 'Dining room light fixture',
        detail: 'A family piece; the sellers will replace it with a builder fixture.' },
      { kind: 'excluded', item: 'Garage shelving' },
      { kind: 'excluded', item: 'Deep freeze in the utility room' },
      { kind: 'negotiable', item: 'Patio furniture' },
      { kind: 'negotiable', item: 'Snow blower' },
    ],
    disclosures: [
      {
        id: 'disc-water-2021',
        factKey: 'basement.water_intrusion_history',
        title: 'Basement water intrusion, 2021',
        detail: 'Water entered the northeast corner of the basement during heavy ' +
                'rainfall in June 2021. The cause was traced to a downspout ' +
                'discharging against the foundation.',
        occurredOn: '2021-06-18',
        remediated: true,
        remediationDetail: 'Downspouts extended and the grade rebuilt by Foothills ' +
                           'Landscaping in August 2021; affected drywall and ' +
                           'underlay replaced. Invoice on file. No recurrence since.',
        reviewed: true,
      },
    ],
  };

  store.load(record);
  seedClaims(store);
  return store;
}

function room(id: string, key: string, name: string, sortOrder: number, adjacency: string[]) {
  return { id, key, name, sortOrder, adjacency, dimensions: null, description: null };
}

type Seed = {
  key: string;
  value: string;
  source: 'agent_input' | 'document' | 'mls' | 'seller_disclosure' | 'public_data';
  doc?: string;
  page?: number;
  snippet?: string;
  room?: string;
};

/**
 * Verified facts, seeded as claims from the documents the demo ships with and
 * then confirmed, exactly as an agent would in the review queue.
 */
const VERIFIED: Seed[] = [
  { key: 'listing.price.list', value: '$899,900', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'listing.possession_date', value: '2026-11-15', source: 'agent_input' },
  { key: 'listing.possession_flexibility', value: 'Sellers can be flexible by up to 30 days either way.', source: 'agent_input' },
  { key: 'listing.occupancy', value: 'owner occupied', source: 'agent_input' },
  { key: 'property.type', value: 'detached', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.year_built', value: '2019', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.storeys', value: '2', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.bedrooms_above_grade', value: '3', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.bedrooms_below_grade', value: '1', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.bathrooms_full', value: '2', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.bathrooms_half', value: '1', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.living_area', value: '2140 sqft', source: 'mls', doc: 'doc-mls', page: 1,
    snippet: 'RMS Above Grade: 2,140 sq ft' },
  { key: 'property.living_area_source', value: 'rms measured', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.lot_size', value: '5,200 sqft', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.title_type', value: 'freehold', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'property.builder', value: 'Crestwood Homes', source: 'agent_input' },
  { key: 'taxes.annual_amount', value: '$4,620.00/yr', source: 'document', doc: 'doc-tax', page: 1,
    snippet: '2025 Total Levy: $4,620.00' },
  { key: 'taxes.tax_year', value: '2025', source: 'document', doc: 'doc-tax', page: 1 },
  { key: 'taxes.assessed_value', value: '$872,000', source: 'document', doc: 'doc-tax', page: 1 },

  { key: 'structure.foundation.type', value: 'poured concrete', source: 'agent_input' },
  { key: 'structure.ceiling_height.main', value: '9 ft', source: 'agent_input' },

  { key: 'exterior.roof.material', value: 'architectural shingle', source: 'document', doc: 'doc-roof', page: 1 },
  { key: 'exterior.roof.warranty_years', value: '25', source: 'document', doc: 'doc-roof', page: 2,
    snippet: 'Limited warranty: 25 years, material only' },
  { key: 'exterior.siding.material', value: 'hardie board', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'exterior.windows.glazing', value: 'triple', source: 'agent_input' },
  { key: 'exterior.garage.type', value: 'attached', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'exterior.garage.car_capacity', value: '2', source: 'mls', doc: 'doc-mls', page: 1 },
  { key: 'exterior.garage.heated', value: 'yes', source: 'agent_input' },
  { key: 'exterior.garage.insulated', value: 'yes', source: 'agent_input' },
  { key: 'exterior.parking.spaces_total', value: '4', source: 'agent_input' },
  { key: 'exterior.parking.driveway_material', value: 'concrete', source: 'agent_input' },
  { key: 'exterior.deck.present', value: 'yes', source: 'agent_input' },
  { key: 'exterior.deck.material', value: 'composite', source: 'agent_input' },
  { key: 'exterior.deck.year_built', value: '2021', source: 'agent_input' },
  { key: 'exterior.deck.permitted', value: 'yes', source: 'document', doc: 'doc-permit', page: 1,
    snippet: 'Permit BP2021-44182 — rear deck, final inspection passed 2021-09-02' },
  { key: 'exterior.yard.orientation', value: 'south', source: 'agent_input' },

  { key: 'mechanical.heating.type', value: 'forced air gas', source: 'agent_input' },
  { key: 'mechanical.furnace.install_year', value: 'Sept 2019', source: 'document',
    doc: 'doc-furnace', page: 1,
    snippet: 'Installed: Sept 2019 — Lennox EL296V, high efficiency' },
  { key: 'mechanical.furnace.make', value: 'Lennox', source: 'document', doc: 'doc-furnace', page: 1 },
  { key: 'mechanical.furnace.efficiency', value: '96% AFUE', source: 'document', doc: 'doc-furnace', page: 1 },
  { key: 'mechanical.furnace.owned_or_rented', value: 'owned', source: 'agent_input' },
  { key: 'mechanical.furnace.last_serviced', value: 'October 2025', source: 'agent_input' },
  { key: 'mechanical.cooling.type', value: 'central ac', source: 'agent_input' },
  { key: 'mechanical.ac.install_year', value: '2019', source: 'agent_input' },
  { key: 'mechanical.water_heater.type', value: 'tank gas', source: 'agent_input' },
  { key: 'mechanical.water_heater.install_year', value: '2019', source: 'agent_input' },
  { key: 'mechanical.water_heater.owned_or_rented', value: 'owned', source: 'agent_input' },
  { key: 'mechanical.ventilation.hrv_present', value: 'yes', source: 'agent_input' },
  { key: 'electrical.service_amperage', value: '200 amps', source: 'agent_input' },
  { key: 'electrical.panel.type', value: 'breakers', source: 'agent_input' },
  { key: 'electrical.wiring.type', value: 'copper', source: 'agent_input' },
  { key: 'plumbing.supply_material', value: 'pex', source: 'agent_input' },
  { key: 'plumbing.sump_pump.present', value: 'yes', source: 'agent_input' },
  { key: 'plumbing.backwater_valve', value: 'yes', source: 'agent_input' },

  { key: 'kitchen.renovation_year', value: '2023', source: 'agent_input' },
  { key: 'kitchen.counter.material', value: 'quartz', source: 'agent_input' },
  { key: 'kitchen.island.present', value: 'yes', source: 'agent_input' },
  { key: 'kitchen.island.seating', value: '4', source: 'agent_input' },
  { key: 'kitchen.pantry', value: 'Walk-in pantry off the kitchen', source: 'agent_input' },
  { key: 'kitchen.appliance.refrigerator.install_year', value: '2023', source: 'agent_input' },
  { key: 'kitchen.appliance.refrigerator.included', value: 'yes', source: 'agent_input' },
  { key: 'kitchen.appliance.stove.type', value: 'gas', source: 'agent_input' },
  { key: 'kitchen.appliance.stove.install_year', value: '2023', source: 'agent_input' },
  { key: 'kitchen.appliance.stove.included', value: 'yes', source: 'agent_input' },
  { key: 'kitchen.appliance.dishwasher.included', value: 'yes', source: 'agent_input' },
  { key: 'kitchen.gas_line_available', value: 'yes', source: 'agent_input' },
  { key: 'kitchen.flooring', value: 'Luxury vinyl plank', source: 'agent_input' },

  { key: 'bathrooms.ensuite.present', value: 'yes', source: 'agent_input' },
  { key: 'bathrooms.ensuite.piece_count', value: '5', source: 'agent_input' },
  { key: 'bathrooms.ensuite.double_vanity', value: 'yes', source: 'agent_input' },
  { key: 'bathrooms.ensuite.shower_type', value: 'Tiled walk-in shower with a glass door', source: 'agent_input' },
  { key: 'bathrooms.basement.present', value: 'yes', source: 'agent_input' },
  { key: 'bathrooms.laundry.location', value: 'Upper floor, next to the bedrooms', source: 'agent_input' },
  { key: 'bathrooms.laundry.washer_dryer_included', value: 'yes', source: 'agent_input' },

  { key: 'interior.flooring.main_level', value: 'luxury vinyl plank', source: 'agent_input' },
  { key: 'interior.fireplace.present', value: 'yes', source: 'agent_input' },
  { key: 'interior.fireplace.type', value: 'gas', source: 'agent_input' },
  { key: 'interior.fireplace.count', value: '1', source: 'agent_input' },
  { key: 'interior.layout.open_concept', value: 'yes', source: 'agent_input' },
  { key: 'interior.layout.bonus_room', value: 'yes', source: 'agent_input' },
  { key: 'interior.windows.coverings_included', value: 'yes', source: 'agent_input' },
  { key: 'interior.closets.primary_type', value: 'Walk-in closet', source: 'agent_input' },
  { key: 'interior.smoking_history', value: 'No smoking in the home.', source: 'seller_disclosure',
    doc: 'doc-disclosure', page: 2 },

  { key: 'basement.present', value: 'yes', source: 'agent_input' },
  { key: 'basement.type', value: 'full', source: 'agent_input' },
  { key: 'basement.finished_status', value: 'finished', source: 'agent_input' },
  { key: 'basement.finished_area', value: '860 sqft', source: 'agent_input' },
  { key: 'basement.development_year', value: '2019', source: 'agent_input' },
  { key: 'basement.development_permitted', value: 'yes', source: 'document', doc: 'doc-permit', page: 2,
    snippet: 'Permit BP2019-10233 — basement development, final inspection passed 2019-12-11' },
  { key: 'basement.ceiling_height', value: '8.5 ft', source: 'agent_input' },
  // The most-asked question in the demo, answered honestly (§17).
  { key: 'basement.suite_status', value: 'not legal', source: 'agent_input' },
  { key: 'basement.suite.separate_entrance', value: 'yes', source: 'agent_input' },
  { key: 'basement.suite.egress_windows', value: 'yes', source: 'agent_input' },
  { key: 'basement.water_intrusion_history',
    value: 'Water entered the northeast corner during heavy rain in June 2021.',
    source: 'seller_disclosure', doc: 'doc-disclosure', page: 3,
    snippet: 'Has water ever entered the basement? YES — June 2021, NE corner, ' +
             'downspout discharge. Repaired.' },
  { key: 'basement.water_intrusion_remediation',
    value: 'Downspouts extended and grade rebuilt in August 2021; drywall and ' +
           'underlay replaced. No recurrence.',
    source: 'document', doc: 'doc-landscaping-invoice', page: 1 },
  { key: 'basement.mould_history', value: 'None reported or observed.',
    source: 'seller_disclosure', doc: 'doc-disclosure', page: 3 },

  { key: 'energy.ev_charger.present', value: 'yes', source: 'agent_input' },
  { key: 'energy.ev_charger.level', value: 'level 2', source: 'agent_input' },
  { key: 'energy.ev_charger.included', value: 'yes', source: 'agent_input' },
  { key: 'safety.smoke_detectors', value: 'Hard-wired smoke detectors on every level.', source: 'agent_input' },
  { key: 'safety.co_detectors', value: 'Carbon monoxide detector on each level.', source: 'agent_input' },
  { key: 'safety.asbestos', value: 'None — the home was built in 2019.', source: 'agent_input' },
  { key: 'security.cameras.recording_notice', value: 'no', source: 'agent_input' },

  { key: 'utilities.water.source', value: 'municipal', source: 'agent_input' },
  { key: 'utilities.sewer.type', value: 'municipal', source: 'agent_input' },
  { key: 'utilities.internet.providers', value: 'Telus fibre and Shaw cable are both available.', source: 'agent_input' },
  { key: 'costs.utilities.annual_gas', value: '$1,180', source: 'agent_input' },
  { key: 'costs.utilities.annual_electricity', value: '$1,460', source: 'agent_input' },
  { key: 'costs.utilities.annual_water', value: '$960', source: 'agent_input' },
  { key: 'costs.utilities.period_covered', value: 'Twelve months ending September 2026.', source: 'agent_input' },
  { key: 'costs.insurance.claims_history', value: 'One claim in 2021 for the basement water intrusion.',
    source: 'seller_disclosure', doc: 'doc-disclosure', page: 4 },
  { key: 'location.schools.catchment',
    value: 'Maple Ridge Elementary (0.6 km) and Bow Valley High School (2.1 km).',
    source: 'public_data' },
  { key: 'location.transit.nearest_stop', value: 'Route 74 stop is a three minute walk on Maple Way.',
    source: 'public_data' },

  { key: 'legal.permits.history', value: 'Two permits on file: basement development 2019, rear deck 2021.',
    source: 'document', doc: 'doc-permit', page: 1 },
  { key: 'legal.permits.open', value: 'No open permits.', source: 'document', doc: 'doc-permit', page: 1 },
  { key: 'legal.permits.unpermitted_work', value: 'None known.', source: 'seller_disclosure',
    doc: 'doc-disclosure', page: 2 },
  { key: 'legal.disclosure.material_latent_defects',
    value: 'The 2021 basement water intrusion, remediated. Nothing else known.',
    source: 'seller_disclosure', doc: 'doc-disclosure', page: 1 },
  { key: 'legal.chattels.included',
    value: 'Refrigerator, gas range, dishwasher, microwave, washer, dryer, window ' +
           'coverings, garage door opener with two remotes, Level 2 EV charger.',
    source: 'agent_input' },
  { key: 'legal.chattels.excluded',
    value: 'Dining room light fixture, garage shelving, deep freeze.', source: 'agent_input' },
  { key: 'legal.chattels.negotiable', value: 'Patio furniture and the snow blower.', source: 'agent_input' },
  { key: 'legal.chattels.leased_items', value: 'Nothing on the property is leased or rented.',
    source: 'agent_input' },
  { key: 'legal.renovation.major_history',
    value: 'Kitchen renovated 2023; composite deck built 2021; basement developed 2019.',
    source: 'agent_input' },
];

/** Facts the agent reviewed and could not answer — a finished state, not a hole (§0.3). */
const UNKNOWNS: { key: string; reason: 'seller_does_not_know' | 'no_documentation' | 'will_follow_up' }[] = [
  { key: 'exterior.windows.replacement_year',        reason: 'seller_does_not_know' },
  { key: 'kitchen.appliance.dishwasher.install_year', reason: 'seller_does_not_know' },
  { key: 'exterior.roof.warranty_transferable',      reason: 'will_follow_up' },
  { key: 'kitchen.appliance.dishwasher.make',        reason: 'no_documentation' },
  { key: 'exterior.eavestrough.material',            reason: 'no_documentation' },
  { key: 'interior.paint.year',                      reason: 'seller_does_not_know' },
  { key: 'mechanical.ductwork.cleaned_year',         reason: 'no_documentation' },
  { key: 'energy.insulation.attic_r_value',          reason: 'will_follow_up' },
];

function seedClaims(store: InMemoryStore): void {
  for (const seed of VERIFIED) {
    const claim = store.addClaim(DEMO_PROPERTY_ID, {
      factKey: seed.key,
      roomId: seed.room ?? null,
      valueRaw: seed.value,
      sourceType: seed.source,
      sourceDocumentId: seed.doc ?? null,
      sourcePage: seed.page ?? null,
      sourceSnippet: seed.snippet ?? null,
      assertedBy: seed.source === 'agent_input' ? DEMO_AGENT_ID : null,
      status: 'pending',
    });
    store.confirmClaim(DEMO_PROPERTY_ID, claim.id, DEMO_AGENT_ID);
  }

  for (const unknown of UNKNOWNS) {
    store.markUnknown(DEMO_PROPERTY_ID, unknown.key, unknown.reason);
  }

  // Facts the agent has chosen to keep private. They are resolved and verified,
  // and they must never reach a fact pack.
  store.addClaim(DEMO_PROPERTY_ID, {
    factKey: 'legal.seller.reason_for_selling',
    valueRaw: 'Relocating for work in the spring.',
    sourceType: 'agent_input', assertedBy: DEMO_AGENT_ID, status: 'pending',
  });
  const privateClaim = store.getClaims(DEMO_PROPERTY_ID).at(-1)!;
  store.confirmClaim(DEMO_PROPERTY_ID, privateClaim.id, DEMO_AGENT_ID);

  // The seeded conflict (§17): the MLS sheet says the roof is 2017, the seller
  // disclosure says 2018. Both claims stand as pending until the agent resolves
  // it, and because the roof year is weighted 10, it blocks publishing.
  store.addClaim(DEMO_PROPERTY_ID, {
    factKey: 'exterior.roof.replacement_year',
    valueRaw: '2017',
    sourceType: 'mls',
    sourceDocumentId: 'doc-mls',
    sourcePage: 2,
    sourceSnippet: 'Roof: asphalt shingle, replaced 2017',
    status: 'pending',
  });
  store.addClaim(DEMO_PROPERTY_ID, {
    factKey: 'exterior.roof.replacement_year',
    valueRaw: '2018',
    sourceType: 'seller_disclosure',
    sourceDocumentId: 'doc-disclosure',
    sourcePage: 2,
    sourceSnippet: 'Roof replaced — 2018 (Summit Roofing)',
    status: 'pending',
  });
}
