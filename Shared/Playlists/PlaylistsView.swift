import Defaults
import Siesta
import SwiftUI

struct PlaylistsView: View {
    @State private var selectedPlaylistID: Playlist.ID = ""

    @State private var showingNewPlaylist = false
    @State private var createdPlaylist: Playlist?

    @State private var showingEditPlaylist = false
    @State private var editedPlaylist: Playlist?

    @StateObject private var channelPlaylist = Store<ChannelPlaylist>()
    @StateObject private var userPlaylist = Store<Playlist>()

    @ObservedObject private var accounts = AccountsModel.shared
    private var player = PlayerModel.shared
    @ObservedObject private var model = PlaylistsModel.shared

    @Namespace private var focusNamespace

    var items: [ContentItem] {
        var videos = currentPlaylist?.videos ?? []

        if videos.isEmpty {
            videos = userPlaylist.item?.videos ?? channelPlaylist.item?.videos ?? []

            if !accounts.app.userPlaylistsEndpointIncludesVideos {
                var i = 0

                for index in videos.indices {
                    var video = videos[index]
                    video.indexID = "\(i)"
                    i += 1
                    videos[index] = video
                }
            }
        }

        return ContentItem.array(of: videos)
    }

    private var resource: Resource? {
        guard let playlist = currentPlaylist else { return nil }

        let resource = accounts.api.playlist(playlist.id)

        if accounts.app.userPlaylistsUseChannelPlaylistEndpoint {
            resource?.addObserver(channelPlaylist)
        } else {
            resource?.addObserver(userPlaylist)
        }

        return resource
    }

    var body: some View {
        BrowserPlayerControls {
            SignInRequiredView(title: "Playlists".localized()) {
                Section {
                    VStack {
                        #if os(tvOS)
                            toolbar
                        #endif
                        if currentPlaylist != nil, items.isEmpty {
                            hintText("Playlist is empty\n\nTap and hold on a video and then \n\"Add to Playlist\"".localized())
                        } else if model.all.isEmpty {
                            hintText("You have no playlists\n\nTap on \"New Playlist\" to create one".localized())
                        } else {
                            Group {
                                #if os(tvOS)
                                    HorizontalCells(items: items)
                                        .padding(.top, 40)
                                    Spacer()
                                #else
                                    VerticalCells(items: items)
                                        .environment(\.scrollViewBottomPadding, 70)
                                #endif
                            }
                            .environment(\.currentPlaylistID, currentPlaylist?.id)
                        }
                    }
                }
            }
        }
        .onAppear {
            model.load()
            resource?.load()
        }
        .onChange(of: accounts.current) { _ in
            model.load(force: true)
            resource?.load()
        }
        .onChange(of: currentPlaylist) { _ in
            channelPlaylist.clear()
            userPlaylist.clear()
            resource?.load()
        }
        .onChange(of: model.reloadPlaylists) { _ in
            resource?.load()
        }
        #if os(iOS)
        .refreshControl { refreshControl in
            model.load(force: true) {
                model.reloadPlaylists.toggle()
                refreshControl.endRefreshing()
            }
        }
        .backport
        .refreshable {
            DispatchQueue.main.async {
                model.load(force: true) { model.reloadPlaylists.toggle() }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                playlistsMenu
            }
        }
        #endif
        #if os(tvOS)
        .fullScreenCover(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
            PlaylistFormView(playlist: $createdPlaylist)
        }
        .fullScreenCover(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
            PlaylistFormView(playlist: $editedPlaylist)
        }
        .focusScope(focusNamespace)
        #else
        .background(
            EmptyView()
                .sheet(isPresented: $showingNewPlaylist, onDismiss: selectCreatedPlaylist) {
                    PlaylistFormView(playlist: $createdPlaylist)
                }
        )
        .background(
            EmptyView()
                .sheet(isPresented: $showingEditPlaylist, onDismiss: selectEditedPlaylist) {
                    PlaylistFormView(playlist: $editedPlaylist)
                }
        )
        #endif

        #if !os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            model.load()
            resource?.loadIfNeeded()
        }
        #endif
        #if !os(tvOS)
        .background(
            Button("Refresh") {
                resource?.load()
            }
            .keyboardShortcut("r")
            .opacity(0)
        )
        #endif
    }

    #if os(iOS)
        var playlistsMenu: some View {
            Menu {
                selectPlaylistButton

                Section {
                    if let currentPlaylist {
                        playButton

                        editPlaylistButton

                        FavoriteButton(item: FavoriteItem(section: .playlist(currentPlaylist.id)))
                            .labelStyle(.iconOnly)
                    }
                }
                newPlaylistButton
            } label: {
                HStack(spacing: 12) {
                    Text(currentPlaylist?.title ?? "Playlists")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .transaction { t in t.animation = nil }
            }
        }
    #endif

    #if os(tvOS)
        var toolbar: some View {
            HStack {
                if model.isEmpty {
                    Text("No Playlists")
                        .foregroundColor(.secondary)
                } else {
                    Text("Current Playlist")
                        .foregroundColor(.secondary)

                    selectPlaylistButton
                }

                if let playlist = currentPlaylist {
                    editPlaylistButton

                    FavoriteButton(item: FavoriteItem(section: .playlist(playlist.id)))
                        .labelStyle(.iconOnly)

                    playButton
                }

                Spacer()

                newPlaylistButton
                    .padding(.leading, 40)
            }
            .labelStyle(.iconOnly)
        }
    #endif

    func hintText(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        #if os(macOS)
            .background(Color.secondaryBackground)
        #endif
    }

    func selectCreatedPlaylist() {
        guard createdPlaylist != nil else {
            return
        }

        model.load(force: true) {
            if let id = createdPlaylist?.id {
                selectedPlaylistID = id
            }

            self.createdPlaylist = nil
        }
    }

    func selectEditedPlaylist() {
        if editedPlaylist.isNil {
            selectedPlaylistID = ""
        }

        model.load(force: true) {
            self.selectedPlaylistID = editedPlaylist?.id ?? ""

            self.editedPlaylist = nil
        }
    }

    var selectPlaylistButton: some View {
        #if os(tvOS)
            Button(currentPlaylist?.title ?? "Select playlist") {
                guard currentPlaylist != nil else {
                    return
                }

                selectedPlaylistID = model.all.next(after: currentPlaylist!)?.id ?? ""
            }
            .lineLimit(1)
            .contextMenu {
                ForEach(model.all) { playlist in
                    Button(playlist.title) {
                        selectedPlaylistID = playlist.id
                    }
                }

                Button("Cancel", role: .cancel) {}
            }
        #else
            Picker("Current Playlist", selection: $selectedPlaylistID) {
                ForEach(model.all) { playlist in
                    Text(playlist.title).tag(playlist.id)
                }
            }
        #endif
    }

    var editPlaylistButton: some View {
        Button(action: {
            self.editedPlaylist = self.currentPlaylist
            self.showingEditPlaylist = true
        }) {
            Label("Edit Playlist", systemImage: "rectangle.and.pencil.and.ellipsis")
        }
    }

    var newPlaylistButton: some View {
        Button(action: { self.showingNewPlaylist = true }) {
            Label("New Playlist", systemImage: "plus")
        }
    }

    private var playButton: some View {
        Button {
            player.play(items.compactMap(\.video))
        } label: {
            Label("Play", systemImage: "play")
        }
        .contextMenu {
            Button {
                player.play(items.compactMap(\.video), shuffling: true)
            } label: {
                Label("Shuffle", systemImage: "shuffle")
            }
        }
    }

    private var currentPlaylist: Playlist? {
        if selectedPlaylistID.isEmpty {
            DispatchQueue.main.async {
                self.selectedPlaylistID = model.all.first?.id ?? ""
            }
        }
        return model.find(id: selectedPlaylistID) ?? model.all.first
    }
}

struct PlaylistsView_Provider: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PlaylistsView()
        }
    }
}
