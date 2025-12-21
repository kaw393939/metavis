import ArgumentParser

@main
struct MetaVis: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "metavis",
        abstract: "MetaVis Rendering CLI",
        subcommands: [VerifyFITSVideoCommand.self, FeedbackCommand.self, AskExpertCommand.self, InspectCommand.self, GenerateCompositeCommand.self]
    )
}
