#  BitNexus Client

**BitNexus** is a modern, federated Torrent Index Client Hub built with **Flutter**. It features a sleek "Aditawa-style" dark UI, magnet link parsing, and seamless integration with a Python-based federated node.

## ✨ Features

-   **Modern UI/UX**: Dark mode with neon green accents (`#00FF87`), glassmorphism effects, and smooth animations.
-   **Magnet Parser**: Automatically extract Title and Info-Hash from raw magnet links.
-   **Federated Search**: Connect to any BitNexus-compatible node to browse and search torrents.
-   **Publish Releases**: Submit new torrents directly to the node with category tagging.
-   **Cross-Platform**: Runs on Web, Windows, Android, Linux, and macOS.

## 🚀 Getting Started

### Prerequisites

-   [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.24+)
-   [Git](https://git-scm.com/)
-   A running BitNexus Server (Python/Flask) or access to a public node.

### Installation

1.  Clone the repository:
    ```bash
    git clone https://github.com/tetolinuxs/torrent-client.git
    cd torrent-client
    ```

2.  Install dependencies:
    ```bash
    flutter pub get
    ```

3.  Run the app:
    ```bash
    flutter run -d chrome
    # Or for desktop:
    flutter run -d windows
    ```

## ⚙️ Configuration

By default, the client connects to `http://127.0.0.1:5000`. You can change this in the **Node Settings** tab within the app.

### API Endpoints

The client expects the following endpoints from the server:

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/api/feed?q=<query>` | Fetch list of torrents. Supports optional search query. |
| `POST` | `/api/submit` | Submit a new torrent. Body: `title`, `info_hash`, `magnet_link`, `category`, `size`. |

## 🛠️ Tech Stack

-   **Frontend**: Flutter (Dart)
-   **State Management**: `setState` (Simple)
-   **HTTP Client**: `http` package
-   **Icons**: Material Icons & Cupertino Icons
-   **Backend**: Python (Flask) - *See [torrent-server](https://github.com/tetolinuxs/torrent-server)*

## 📸 Screenshots

*(Add screenshots here once you have them)*

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📄 License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
