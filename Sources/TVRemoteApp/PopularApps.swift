import TVRemoteCore

/// Known Tizen app IDs offered for shortcuts. SmartThings can't list installed apps, so the
/// picker checks these against the TV and shows only the installed ones (with the TV's names).
/// Away from the TV's network, the whole list is shown instead.
enum PopularApps {
    static let all: [TVApp] = [
        TVApp(id: "111299001912", name: "YouTube"),
        TVApp(id: "3201907018807", name: "Netflix"),
        TVApp(id: "3201910019365", name: "Prime Video"),
        TVApp(id: "3201901017640", name: "Disney+"),
        TVApp(id: "3202301029760", name: "HBO Max"),
        TVApp(id: "3201807016597", name: "Apple TV"),
        TVApp(id: "3201908019041", name: "Apple Music"),
        TVApp(id: "3201606009684", name: "Spotify"),
        TVApp(id: "3202203026841", name: "Twitch"),
        TVApp(id: "3201703012065", name: "YouTube Kids"),
        TVApp(id: "3201512006963", name: "Plex"),
        TVApp(id: "3201710015037", name: "Samsung TV Plus"),
        TVApp(id: "3201804016153", name: "Hotstar"),
        TVApp(id: "3201703012079", name: "Viu"),
        TVApp(id: "3201809016736", name: "Vidio"),
        TVApp(id: "3201905018355", name: "iQIYI"),
        TVApp(id: "3202010022079", name: "Browser"),
    ]
}
