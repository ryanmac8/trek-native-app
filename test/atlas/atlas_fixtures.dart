/// A full `GET /api/addons/atlas/stats` response, in the shape
/// `AtlasService.stats` returns for a user with trips.
Map<String, dynamic> fullStatsJson() => {
  'countries': [
    {
      'code': 'NZ',
      'placeCount': 12,
      'tripCount': 2,
      'firstVisit': '2024-02-01',
      'lastVisit': '2025-03-10',
      'status': 'visited',
    },
    {
      'code': 'JP',
      'placeCount': 4,
      'tripCount': 1,
      'firstVisit': null,
      'lastVisit': null,
      'status': 'planned',
    },
    {
      'code': 'PE',
      'placeCount': 1,
      'tripCount': 1,
      'firstVisit': null,
      'lastVisit': null,
      'status': 'idea',
    },
  ],
  'stats': {
    'totalTrips': 5,
    'totalPlaces': 17,
    'totalCountries': 1,
    'totalCountriesPlanned': 1,
    'totalCountriesIdea': 1,
    'totalDays': 23,
    'totalCities': 6,
  },
  'mostVisited': {
    'code': 'NZ',
    'placeCount': 12,
    'tripCount': 2,
    'firstVisit': '2024-02-01',
    'lastVisit': '2025-03-10',
    'status': 'visited',
  },
  'continents': {'Oceania': 1},
  'continentsPlanned': {'Asia': 1},
  'lastTrip': {
    'id': 20,
    'title': 'New Zealand',
    'start_date': '2025-03-01',
    'end_date': '2025-03-10',
    'countryCode': 'NZ',
  },
  'nextTrip': {
    'id': 21,
    'title': 'Japan',
    'start_date': '2026-10-04',
    'daysUntil': 10,
  },
  'streak': 3,
  'firstYear': 2024,
  'tripsThisYear': 2,
};

/// Trek's reduced response for a user with no trips — only manually marked
/// countries, no status on them, and a partial `stats` object.
Map<String, dynamic> zeroTripStatsJson() => {
  'countries': [
    {
      'code': 'FR',
      'placeCount': 0,
      'tripCount': 0,
      'firstVisit': null,
      'lastVisit': null,
    },
  ],
  'trips': <dynamic>[],
  'stats': {
    'totalTrips': 0,
    'totalPlaces': 0,
    'totalCountries': 1,
    'totalDays': 0,
  },
};
