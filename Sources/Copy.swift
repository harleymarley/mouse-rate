// Copy.swift
// Every line of text the tests show, in plain and cheeky versions.
// Cheeky mode is on by default and can be switched off at the top of the window.

import Foundation

enum Copy {
    static func pick(_ lines: [String]) -> String { lines.randomElement() ?? "" }

    // MARK: step cards

    struct StepText { let title: String; let text: String; let quip: String }

    static func stepIntro(_ step: Step, cheeky: Bool) -> StepText {
        if !cheeky {
            switch step {
            case .polling: return StepText(title: "Polling rate", text: "Move your mouse in steady circles for about 5 seconds. We count how many reports it sends each second.", quip: "")
            case .buttons: return StepText(title: "Buttons and scroll", text: "Press every button on your mouse once, side buttons too. Then roll the wheel up and down.", quip: "")
            case .doubleClick: return StepText(title: "Double-click", text: "Click the box slowly, about once a second, 20 times. We're checking for single clicks that count twice.", quip: "")
            case .clickSpeed: return StepText(title: "Click speed", text: "Click as fast as you can for 5 seconds. The timer starts on your first click.", quip: "")
            case .report: return StepText(title: "Your mouse report", text: "", quip: "")
            }
        }
        switch step {
        case .polling: return pick2([
            StepText(title: "Let's warm you up.", text: "Move your mouse in slow, steady circles for 5 seconds. Don't stop until we say so.", quip: "We'll be gentle. At first."),
            StepText(title: "Let's start slow. Very slow.", text: "Move your mouse in circles for 5 seconds. Nice and steady. No stopping halfway.", quip: "Relax. You're in good hands.")])
        case .buttons: return pick2([
            StepText(title: "Now let's find your buttons.", text: "Press every button once. Yes, the side ones too. Then roll the wheel up and down.", quip: "Most people forget the side ones. Don't be most people."),
            StepText(title: "Time to explore.", text: "Press every single button once, side buttons included. Then roll the wheel up and down. Take your time.", quip: "We're not judging. Much.")])
        case .doubleClick: return pick2([
            StepText(title: "Now, slowly.", text: "Click once a second, 20 times. We're checking whether your mouse finishes too early.", quip: "It happens to a lot of mice. We don't talk about it."),
            StepText(title: "Slow it down for us.", text: "One click a second, 20 times. Any click that counts twice means your switch can't hold it together.", quip: "Patience. The good stuff takes time.")])
        case .clickSpeed: return pick2([
            StepText(title: "Okay. Now fast.", text: "Click as fast as you can for 5 seconds. The timer starts on your first click.", quip: "Show us what that finger can do."),
            StepText(title: "Faster. Harder. Go.", text: "Click as fast as you can for 5 seconds. The timer starts when you do.", quip: "We mean the button. Obviously.")])
        case .report: return StepText(title: "Your mouse report", text: "", quip: "")
        }
    }

    private static func pick2(_ options: [StepText]) -> StepText { options.randomElement()! }

    static func finalCard(cheeky: Bool) -> StepText {
        cheeky
            ? StepText(title: pick(["That was fun for us too.", "Wow. We need a minute.", "Was it good for you?"]),
                       text: "Here's everything your mouse did. Copy it for the comments, or go again. We won't tell anyone.",
                       quip: pick(["Same time next week?", "Call us.", "Don't be a stranger."]))
            : StepText(title: "Here's your mouse report", text: "Everything in one place. Copy it for the comments if you like.", quip: "")
    }

    // MARK: polling

    static func pollLive(progress: Double, paused: Bool, cheeky: Bool) -> String {
        if !cheeky { return paused ? "Keep moving. Pauses don't count." : "Keep going" }
        if paused { return pick(["Hey, why'd you stop?", "Don't leave me hanging", "Don't tease me like that", "Come back, I was close", "Cramp? It happens."]) }
        switch progress {
        case ..<0.25: return pick(["That's it, keep going", "Ooh, warm hands", "Mmm, good rhythm", "Round and round. Lovely."])
        case ..<0.5: return pick(["Don't stop now", "You're a natural", "Is this your first time? It doesn't show"])
        case ..<0.75: return pick(["Yes, just like that", "Right there. Don't change a thing", "The neighbors can hear your mouse pad"])
        case ..<0.92: return pick(["Faster. Almost there", "So close", "Don't you dare stop", "Oh my. Oh my."])
        default: return pick(["Almost there", "Almost. Almost.", "Here it comes"])
        }
    }

    static func pollIdle(cheeky: Bool) -> String {
        cheeky ? "Move your mouse in circles. Don't be shy." : "Move your mouse in steady circles"
    }

    static func pollDone(cheeky: Bool) -> String {
        cheeky ? pick(["Done. Was it good for you?", "Done. Want to talk about it?", "Done. Same time tomorrow?"]) : "Done"
    }

    static func pollQuip(_ hz: Int, cheeky: Bool) -> String {
        guard cheeky else { return "" }
        if hz >= 1500 { return pick(["Okay, show-off.", "Easy, tiger.", "Is it hot in here, or is it just your mouse?", "We need a minute after that."]) }
        if hz >= 700 { return pick(["Buttery.", "Oh, that felt good.", "A thousand times a second. Somebody's been working out.", "Smooth operator."]) }
        if hz >= 200 { return pick(["Not bad. We've had better, but we've had worse.", "Decent. Room to grow, if you know what we mean."]) }
        return pick(["Is that all you got?", "That's okay. It happens.", "Some mice are growers, not showers.", "Let's blame the Bluetooth."])
    }

    static func pollNote(_ hz: Int) -> String {
        if hz < 200 { return "That's office mouse territory. It's what you get from most Bluetooth mice. It works, but on a fast screen the cursor can feel a step behind your hand." }
        if hz < 700 { return "That's in the middle. Better than most office mice, below what a gaming mouse does on its receiver." }
        if hz < 1500 { return "That's a gaming-grade rate. One update every millisecond. The cursor goes where your hand goes." }
        return "That's a high-end rate. Most people will never feel the difference past 1000Hz, but your mouse can do it."
    }

    // MARK: buttons

    static func buttonLine(_ part: MousePart, cheeky: Bool) -> String {
        guard cheeky else { return "\(part.label) works." }
        switch part {
        case .left: return pick(["Right there.", "Yes, that one.", "Firm. We like that.", "Ooh, decisive.", "Click it like you mean it.", "Left click. A classic for a reason."])
        case .right: return pick(["Ooh, the right one.", "Exploring, are we?", "Right click. Opening up some options, are we?", "Nobody right-clicks on a first date."])
        case .middle: return pick(["The middle one. Nobody ever finds the middle one.", "Ooh, you went for the wheel. Bold.", "That one takes experience."])
        case .back: return pick(["Back there? Bold move.", "Ooh, a little to the back.", "Didn't think you'd go there."])
        case .forward: return pick(["Forward. Eager, aren't we?", "Someone knows their way around.", "Not shy at all, are you?"])
        case .up: return pick(["Up, up, up.", "Higher. Okay.", "Nice and steady."])
        case .down: return pick(["Deeper. Okay.", "How far down are we going?", "Take it slow."])
        case .tiltLeft, .tiltRight: return pick(["Ooh, a tilt.", "Leaning in, are we?", "Didn't know it did that, did you?"])
        }
    }

    static func buttonsIntro(cheeky: Bool) -> String { cheeky ? "Hitting the right spot is important. Find them all." : "" }
    static func buttonsSide(cheeky: Bool) -> String { cheeky ? "Side buttons too, if you've got them." : "Got side buttons? Press them too." }
    static func buttonsAll(cheeky: Bool) -> String {
        cheeky ? pick(["You found every spot. Impressive.", "Every single spot. Someone's done this before.", "All of them. We need a cold shower."]) : "Every button works."
    }

    // MARK: double-click

    static func dcLabel(clicks: Int, gapMs: Double?, phantom: Bool, cheeky: Bool) -> String {
        if phantom, let g = gapMs { return (cheeky ? "Whoa, that one came twice" : "Counted twice") + " (\(Int(g)) ms)" }
        if clicks == 0 { return cheeky ? "Slow and steady" : "Click slowly" }
        if clicks >= 20 { return cheeky ? "Done. You can keep going" : "Done. Keep going if you like" }
        guard cheeky else { return "Good. Keep it slow" }
        if let g = gapMs, g < 250 { return pick(["Slow down, there's no rush", "Easy. We have all night"]) }
        switch clicks {
        case 5: return "Ooh, patient"
        case 10: return "Halfway. Keep teasing it"
        case 15: return "Almost done. Hold it together"
        case 18: return "Two more. Breathe"
        default: return clicks % 3 == 0 ? "Mmm. Take your time" : "Easy. Nice and slow"
        }
    }

    static func dcQuip(phantom: Int, cheeky: Bool) -> String {
        guard cheeky else { return "" }
        return phantom == 0
            ? pick(["No premature clicks. Respect.", "Not a single early finish. Impressive self-control.", "Twenty for twenty. Your switch has stamina."])
            : pick(["Happens to the best of us.", "It finished early. Don't worry, it's the switch, not you.", "A little too eager. We've all been there."])
    }

    // MARK: click speed

    static func cpsLabel(left: Double, rate: Double, elapsed: Double, cheeky: Bool) -> String {
        let t = String(format: "%.1fs", left)
        guard cheeky else { return "\(t) left" }
        let alt = Int(elapsed / 1.6) % 2 == 1
        if elapsed < 0.8 { return "\(t). Faster!" }
        if rate >= 10 { return "\(t). " + (alt ? "Whoa, whoa, whoa!" : "Easy, tiger!") }
        if rate >= 7 { return "\(t). " + (alt ? "Harder! I mean faster!" : "Here we go!") }
        return "\(t). " + (alt ? "Put your back into it!" : "Come on, faster!")
    }

    static func cpsQuip(_ score: Double, cheeky: Bool) -> String {
        guard cheeky else { return "" }
        if score < 6 { return pick(["Slow and steady. Some people prefer it that way.", "Saving your energy for later?"]) }
        if score < 9 { return pick(["Respectable. Your finger could go pro.", "Nice rhythm. Very nice rhythm."]) }
        if score < 12 { return pick(["Wow. Somebody practices a lot. At home. Alone.", "That finger needs a cigarette."]) }
        return "Okay, stop. You're making the other mice uncomfortable."
    }

    static func cpsNote(_ score: Double) -> String {
        if score < 6 { return "That's a relaxed pace. Most people land between 6 and 8." }
        if score < 9 { return "That's right around where most people land." }
        if score < 12 { return "That's fast. Faster than most people." }
        return "That's very fast. You've done this before."
    }
}
