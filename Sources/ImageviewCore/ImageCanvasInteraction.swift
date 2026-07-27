public enum ImageCanvasDragIntent: Equatable, Sendable {
    case cropSelection
    case pan
}

public enum ImageCanvasInteraction {
    public static func primaryDragIntent(
        startsInsideImage: Bool,
        optionPressed: Bool
    ) -> ImageCanvasDragIntent? {
        guard startsInsideImage else {
            return nil
        }
        return optionPressed ? .pan : .cropSelection
    }
}
