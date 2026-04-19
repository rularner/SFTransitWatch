# SF Transit Watch

An Apple Watch app that shows nearby bus stops and real-time arrival times for San Francisco transit using the 511.org API.

## Features

- **Real-time 511.org Integration**: Uses the official 511.org Transit API for live data
- **Location-based Bus Stop Discovery**: Automatically finds nearby bus stops using GPS
- **Real-time Arrival Times**: Shows upcoming bus arrivals with live updates from 511.org
- **Distance Information**: Displays how far each stop is from your current location
- **Route Information**: Shows which bus routes serve each stop
- **Favorite Stops**: Mark frequently used stops as favorites for quick access
- **Favorites First**: Favorite stops appear at the top of the list
- **Siri Integration**: Use voice commands to check bus times hands-free
- **Route-Specific Voice Commands**: Ask for specific bus/train routes by name
- **Pull-to-Refresh**: Manually refresh arrival times by pulling down
- **Auto-refresh**: Automatically updates arrival times every 30 seconds
- **Watch-optimized UI**: Designed specifically for Apple Watch with large touch targets
- **API Key Management**: Built-in settings to configure your 511.org API key

## Screenshots

The app has four main screens:

1. **Nearby Stops**: Shows a list of bus stops near your current location, sorted by distance with favorites first
2. **Arrival Times**: Shows upcoming bus arrivals for a selected stop with route information
3. **Settings**: Configure your 511.org API key and manage favorite stops
4. **Siri Shortcuts**: Set up voice commands for hands-free transit information

## Siri Integration

### Voice Commands

You can use Siri to quickly access transit information:

#### General Commands
- **"Hey Siri, find nearby bus stops"** - Opens the app and shows nearby stops
- **"Hey Siri, check bus times"** - Opens the app to view arrival times
- **"Hey Siri, show me transit times"** - Opens the app for current times
- **"Hey Siri, open SF Transit Watch"** - Launches the app

#### Route-Specific Commands
- **"Hey Siri, when is the next 38 bus"** - Check times for the 38 bus route
- **"Hey Siri, when is the next F train"** - Check times for the F streetcar
- **"Hey Siri, next 14 bus"** - Quick check for the 14 bus
- **"Hey Siri, bus 22 times"** - Get arrival times for the 22 bus
- **"Hey Siri, when is the next N train"** - Check N-Judah train times
- **"Hey Siri, next L bus"** - Get L-Taraval bus times

### Supported Routes

The app recognizes these common San Francisco routes:
- **Bus Routes**: 38, 38R, 14, 14R, 22
- **Streetcar Routes**: F, N, L, K, M, T
- **Express Routes**: Any route with "R" suffix

### Setting Up Siri Shortcuts

1. **Open Settings**: Tap the gear icon in the app
2. **Go to Siri Integration**: Tap "Voice Commands" in the settings
3. **Add Shortcuts**: Tap the "+" button next to any shortcut
4. **Record Your Phrase**: Follow the prompts to record your custom voice command
5. **Test It**: Say "Hey Siri" followed by your custom phrase

### Available Shortcuts

- **Find Nearby Stops**: Locate bus stops near your current location
- **Route-Specific Times**: Check times for specific bus/train routes
- **Check Bus Times**: Get arrival times for specific stops
- **Custom Commands**: Create your own voice phrases for any function

### How Siri Learning Works

The app automatically teaches Siri your preferences:
- When you view arrival times, Siri learns which stops you check
- When you favorite stops, Siri remembers your frequently used locations
- When you view specific routes, Siri learns which routes you use most
- Siri suggests shortcuts based on your usage patterns

### Route-Specific Learning

The app intelligently learns your route preferences:
- **Automatic Route Detection**: Siri recognizes when you ask about specific routes
- **Route Suggestions**: Based on your location and usage, Siri suggests relevant routes
- **Voice Pattern Learning**: Siri adapts to how you naturally ask for route information

## Favorites Feature

### How to Use Favorites

1. **Add to Favorites**: 
   - Tap the star icon next to any bus stop in the list
   - The star will turn yellow to indicate it's favorited

2. **View Favorites**:
   - Favorite stops appear in a separate "Favorites" section at the top
   - They're also marked with a yellow star icon

3. **Remove from Favorites**:
   - Tap the yellow star icon to unfavorite a stop
   - Or use the "Clear All Favorites" option in Settings

4. **Manage Favorites**:
   - Go to Settings to see how many favorites you have
   - Clear all favorites at once if needed

### Favorites Benefits

- **Quick Access**: Favorite stops always appear first
- **Persistent**: Favorites are saved between app launches
- **Visual Indicators**: Yellow stars make favorites easy to spot
- **Easy Management**: Toggle favorites with a single tap

## Setup Instructions

### Prerequisites

- Xcode 15.0 or later
- iOS 17.0+ / watchOS 10.0+
- Apple Developer Account (for device testing)
- Apple Watch (for testing)
- 511.org API key (free)

### Getting Your 511.org API Key

1. **Visit the 511.org Developer Portal**:
   - Go to https://511.org/developers/
   - Click "Get API Key"
   - Fill out the registration form
   - You'll receive your API key via email

2. **API Key Features**:
   - Free for personal use
   - Rate limited (check 511.org documentation)
   - Covers San Francisco Bay Area transit agencies
   - Real-time data for Muni, BART, AC Transit, and more

### Installation

1. **Clone the repository**:
   ```bash
   git clone <repository-url>
   cd SFTransitWatch
   ```

2. **(Optional) Override signing locally**:
   ```bash
   cp Developer.xcconfig.sample Developer.xcconfig
   # Edit Developer.xcconfig and replace YOUR_TEAM_ID with your team ID
   ```
   `Developer.xcconfig` is gitignored and optional — `Config.xcconfig` pulls it
   in with an optional `#include?` directive, so the project builds fine
   without it. Create it only if you want to override signing settings like
   `DEVELOPMENT_TEAM` without editing the project file.

3. **Open in Xcode**:
   ```bash
   open SFTransitWatch.xcodeproj
   ```

3. **Configure your team**:
   - Select the project in Xcode
   - Go to "Signing & Capabilities"
   - Select your development team
   - Update the bundle identifier if needed

4. **Build and Run**:
   - Select your Apple Watch as the target device
   - Press Cmd+R to build and run

5. **Configure API Key**:

   Pick whichever of these is easiest:

   - **On the iPhone app** (recommended): open **Settings** and paste the
     token into **511.org API Key**. The watch picks it up the next time it
     connects.
   - **On the watch**: open the app, tap the settings gear, select
     **Enter API Key**, and paste or dictate the key.
   - **Via text or email**: send yourself a Messages or Mail message
     containing the link
     `https://rularner.github.io/sftransitwatch/key?k=YOUR_API_KEY`
     (replace `YOUR_API_KEY` with the token from 511.org), then open
     that message **on your Apple Watch** and tap the link. The watch
     app is registered as the handler for that URL via Universal
     Links, so the app opens and saves the key automatically. Tapping
     the link on the iPhone just shows a short fallback page — the
     link has to be opened on the watch itself. If the universal link
     isn't active yet, the app also accepts a custom-scheme fallback
     (`sftransitwatch://key/YOUR_API_KEY`).

   See [docs/support.md](docs/support.md#loading-your-api-key-via-text-or-email)
   for more detail on the link method.

6. **Set Up Siri**:
   - Go to Settings > Siri Integration
   - Add voice shortcuts for your most common actions
   - Test the voice commands

### Location Permissions

The app requires location access to find nearby bus stops. When prompted:

1. Tap "Allow While Using App"
2. The app will automatically start finding nearby stops

## 511.org API Integration

### Supported Transit Agencies

- **San Francisco Muni**: Buses, streetcars, and cable cars
- **BART**: Bay Area Rapid Transit
- **AC Transit**: Alameda-Contra Costa Transit
- **Caltrain**: Peninsula commuter rail
- **VTA**: Santa Clara Valley Transportation Authority

### API Endpoints Used

- **StopMonitoring**: Real-time arrival predictions
- **StopPlace**: Nearby transit stops
- **VehicleMonitoring**: Live vehicle locations (future)

### Data Format

The app parses 511.org's XML responses:
```xml
<MonitoredVehicleJourney>
  <LineRef>38</LineRef>
  <DirectionRef>Downtown</DirectionRef>
  <MonitoredCall>
    <ExpectedDepartureTime>2024-01-15T14:30:00Z</ExpectedDepartureTime>
  </MonitoredCall>
</MonitoredVehicleJourney>
```

## Project Structure

```
SFTransitWatch/
├── SFTransitWatchApp.swift          # Main app entry point
├── ContentView.swift                # Root view with navigation
├── BusStopListView.swift            # List of nearby stops with favorites
├── BusArrivalView.swift             # Arrival times for selected stop
├── SettingsView.swift               # API key and favorites management
├── SiriShortcutsView.swift          # Siri shortcuts configuration
├── SiriManager.swift                # Siri integration and intent handling
├── FavoritesManager.swift           # Favorites storage and management
├── LocationManager.swift            # GPS location handling
├── TransitAPI.swift                 # 511.org API integration
├── BusStop.swift                    # Data model for bus stops
├── BusArrival.swift                 # Data model for arrivals
└── Assets.xcassets/                 # App icons and resources
```

## Data Models

### BusStop
- `id`: Unique identifier from 511.org
- `name`: Stop name (e.g., "Market St & 4th St")
- `code`: Stop code (e.g., "M4")
- `latitude/longitude`: GPS coordinates from 511.org
- `routes`: Array of bus routes serving this stop
- `isFavorite`: Whether this stop is marked as favorite

### BusArrival
- `route`: Bus route number from 511.org
- `destination`: Final destination
- `arrivalTime`: Scheduled arrival time from 511.org
- `minutesAway`: Minutes until arrival
- `isRealTime`: Whether this is live data from 511.org

## API Error Handling

The app includes robust error handling:

- **Network Errors**: Falls back to sample data
- **Invalid API Key**: Shows configuration prompt
- **No Data**: Displays appropriate empty states
- **Location Errors**: Graceful degradation

## Customization

### Adding New Transit Agencies

1. Update `TransitAPI.swift` with new agency codes
2. Add new API endpoints if needed
3. Update XML parsing for agency-specific formats

### UI Customization

- Colors: Modify `AccentColor.colorset`
- Icons: Replace app icon in `AppIcon.appiconset`
- Fonts: Update text styles in SwiftUI views

## Troubleshooting

### Common Issues

1. **API Key Issues**:
   - Verify your 511.org API key is correct
   - Check if you've exceeded rate limits
   - Ensure the key is saved in Settings

2. **Location not working**:
   - Check location permissions in Watch Settings
   - Ensure GPS is enabled on the paired iPhone

3. **No stops found**:
   - Verify you're in the San Francisco Bay Area
   - Check internet connection
   - Try pulling to refresh

4. **Favorites not saving**:
   - Check if the app has proper permissions
   - Try restarting the app
   - Verify UserDefaults is working

5. **Siri not working**:
   - Ensure Siri is enabled on your Apple Watch
   - Check that shortcuts are properly added
   - Try re-recording your voice commands
   - Verify the app has microphone permissions
   - For route-specific commands, make sure to say the route number clearly

6. **Route commands not recognized**:
   - Speak clearly when saying route numbers
   - Try different phrasings (e.g., "38 bus" vs "route 38")
   - Check that the route exists in the system
   - Ensure you're in an area served by that route

7. **Build errors**:
   - Clean build folder (Cmd+Shift+K)
   - Update Xcode to latest version
   - Check deployment target compatibility

### Debug Mode

For development, the app includes:
- Sample bus stop data as fallback
- Simulated API responses
- Debug logging in console
- Graceful error handling

## Rate Limits

511.org API has rate limits:
- **Free Tier**: 1,000 requests per day
- **Paid Tier**: Higher limits available
- **Caching**: App caches data to minimize requests

## Future Enhancements

- [ ] Real-time vehicle tracking
- [ ] Route planning with 511.org
- [ ] Service alerts from 511.org
- [ ] Accessibility improvements
- [ ] Complications support
- [ ] Offline mode with cached data
- [ ] Multiple transit agencies
- [ ] Push notifications for delays
- [ ] Favorite stop widgets
- [ ] Custom favorite stop names
- [ ] Advanced Siri commands
- [ ] Siri complications
- [ ] Voice feedback for arrival times
- [ ] Route-specific complications
- [ ] Multi-route voice queries

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test on actual Apple Watch
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Create an issue on GitHub
- Check the troubleshooting section
- Review 511.org API documentation
- Contact 511.org for API support

---

**Note**: This app uses the official 511.org Transit API. Please respect their terms of service and rate limits. For production use, consider implementing proper caching and error handling. 