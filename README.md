# CountryMe

Counter for spent days by country.

CountryMe runs quietly in the background, detects which country your phone is currently in, and
keeps a tally of how many distinct days you've spent in each one. Your stats sync across your
devices via iCloud, and a Home Screen widget shows your current country plus your top 3 most
visited — all at a glance, with no need to open the app.

- **Background detection** — uses significant-location-change monitoring (battery-friendly,
  works even when the app is closed) and reverse-geocoding to identify your current country.
- **iCloud sync** — your country stats are stored in SwiftData backed by CloudKit's private
  database, so they follow you across all your signed-in devices.
- **Home Screen widget** — small and medium widgets surface your current country and your
  most-visited countries without opening the app.

For a deeper look at how the detection → persistence → widget pipeline works, how iOS widgets
work under the hood, and where to make common changes, see [ARCHITECTURE.md](ARCHITECTURE.md).
