/// A `GET /api/addons` body in the shape Trek's `AddonsService.list()`
/// returns: enabled add-ons only, a photo provider (listed because Journey
/// is on), Collab sub-features, and the bag-tracking flag.
Map<String, dynamic> addonsResponse({
  bool budget = true,
  bool packing = true,
  bool journey = true,
}) => {
  'collabFeatures': {
    'chat': true,
    'notes': true,
    'links': true,
    'polls': false,
    'whatsnext': true,
  },
  'bagTracking': true,
  'addons': [
    if (packing)
      {
        'id': 'packing',
        'name': 'Lists',
        'type': 'trip',
        'icon': 'ListChecks',
        'enabled': true,
      },
    if (budget)
      {
        'id': 'budget',
        'name': 'Costs',
        'type': 'trip',
        'icon': 'Wallet',
        'enabled': true,
      },
    {
      'id': 'collab',
      'name': 'Collab',
      'type': 'trip',
      'icon': 'Users',
      'enabled': true,
    },
    {
      'id': 'atlas',
      'name': 'Atlas',
      'type': 'global',
      'icon': 'Globe',
      'enabled': true,
    },
    if (journey) ...[
      {
        'id': 'journey',
        'name': 'Journey',
        'type': 'global',
        'icon': 'Compass',
        'enabled': true,
      },
      {
        'id': 'immich',
        'name': 'Immich',
        'type': 'photo_provider',
        'icon': 'Image',
        'enabled': true,
        'config': {},
        'fields': [
          {
            'key': 'immich_url',
            'label': 'Immich URL',
            'input_type': 'url',
            'placeholder': '',
            'hint': null,
            'required': true,
            'secret': false,
            'settings_key': 'immich_url',
            'payload_key': 'immich_url',
            'sort_order': 0,
          },
        ],
      },
    ],
  ],
};
