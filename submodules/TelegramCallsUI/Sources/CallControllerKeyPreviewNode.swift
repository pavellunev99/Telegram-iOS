import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Accelerate
import Postbox
import TelegramCore
import TelegramPresentationData

private let emojiFont = Font.regular(28.0)
private let textFont = Font.regular(15.0)

final class CallControllerKeyNewPreviewNode: ASDisplayNode {

    private let backgroundNode: ASDisplayNode
    private let keyTextNode: ASTextNode
    private let titleTextNode: ASTextNode
    private let descriptionTextNode: ASTextNode
    private let separatorNode: ASDisplayNode
    private let dismissButtonNode: ASButtonNode

    private let peer: Peer
    private let dismiss: () -> Void

    init(keyText: String, strings: PresentationStrings, peer: Peer, isVideo: Bool, dismiss: @escaping () -> Void) {
        self.backgroundNode = ASDisplayNode()
        self.keyTextNode = ASTextNode()
        self.keyTextNode.displaysAsynchronously = false
        self.titleTextNode = ASTextNode()
        self.titleTextNode.displaysAsynchronously = false
        self.descriptionTextNode = ASTextNode()
        self.descriptionTextNode.displaysAsynchronously = false
        self.separatorNode = ASDisplayNode()
        self.dismissButtonNode = ASButtonNode()
        self.dismiss = dismiss
        self.peer = peer

        super.init()

        self.backgroundNode.clipsToBounds = true
        self.backgroundNode.cornerRadius = 20
        self.backgroundNode.backgroundColor = isVideo ? .black.withAlphaComponent(0.5) : .white.withAlphaComponent(0.25)

        self.keyTextNode.attributedText = NSAttributedString(string: keyText, font: Font.regular(42.0), textColor: UIColor.white, paragraphAlignment: .center)

        self.titleTextNode.attributedText = NSAttributedString(string: strings.Call_EncryptionKey_Title, font: Font.semibold(16), textColor: UIColor.white, paragraphAlignment: .center)

        self.descriptionTextNode.attributedText = NSAttributedString(string: strings.Call_EmojiDescription(EnginePeer(peer).compactDisplayTitle).string.replacingOccurrences(of: "%%", with: "%"), font: Font.regular(16), textColor: UIColor.white, paragraphAlignment: .center)
        self.descriptionTextNode.maximumNumberOfLines = 3

        self.separatorNode.backgroundColor = .black.withAlphaComponent(0.1)

        self.dismissButtonNode.titleNode.attributedText = NSAttributedString(string: strings.Common_OK, font: Font.regular(20), textColor: UIColor.white, paragraphAlignment: .center)
        self.dismissButtonNode.titleNode.textAlignment = .center

        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.keyTextNode)
        self.addSubnode(self.titleTextNode)
        self.addSubnode(self.descriptionTextNode)
        self.addSubnode(self.separatorNode)
        self.addSubnode(self.dismissButtonNode)
    }

    override func didLoad() {
        super.didLoad()

        self.dismissButtonNode.addTarget(self, action: #selector(self.tapDismiss), forControlEvents: .touchUpInside)
    }

    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {

        var originY = 20.0
        let inset = 16.0
        let width = size.width - 89.0

        let keyTextSize = self.keyTextNode.measure(CGSize(width: width, height: 300.0))
        transition.updateFrame(node: self.keyTextNode, frame: CGRect(origin: CGPoint(x: floor((width - keyTextSize.width) / 2) + 6.0, y: originY), size: keyTextSize))
        originY += keyTextSize.height + 10.0

        let titleTextSize = self.titleTextNode.measure(CGSize(width: width - inset*2, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: self.titleTextNode, frame: CGRect(origin: CGPoint(x: inset, y: originY), size: CGSize(width: width - inset*2, height: titleTextSize.height)))
        originY += titleTextSize.height + 10.0

        let descriptionTextSize = self.descriptionTextNode.measure(CGSize(width: width - inset*2, height: CGFloat.greatestFiniteMagnitude))
        transition.updateFrame(node: self.descriptionTextNode, frame: CGRect(origin: CGPoint(x: width/2 - descriptionTextSize.width/2, y: originY), size: descriptionTextSize))
        originY += descriptionTextSize.height + 20.0

        transition.updateFrame(node: self.separatorNode, frame: CGRect(x: 0, y: originY, width: width, height: 1))
        originY += inset + 1

        transition.updateFrame(node: self.dismissButtonNode, frame: CGRect(x: inset, y: originY, width: width - inset*2, height: 25))
        originY += 25 + inset

        let backgroundSize = CGSize(width: width, height: originY)
        transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(), size: backgroundSize))

        return backgroundSize
    }

    func animateIn(from rect: CGRect, fromNode: ASDisplayNode) {
        self.isHidden = false
        let duration = 0.5

//        guard let transitionKeyView = fromNode.view.snapshotView(afterScreenUpdates: false) else { return }

//        self.keyTextNode.alpha = 0

        let originFrame = self.frame

        self.frame = rect
        self.alpha = 0

//        let keyTransition = ContainedViewLayoutTransition.animated(duration: duration * 1.2, curve: .spring)
//        self.view.addSubview(transitionKeyView)
//        transitionKeyView.frame = rect
//        keyTransition.updateFrame(view: transitionKeyView, frame: self.keyTextNode.frame) { _ in
//            self.keyTextNode.alpha = 1
//            transitionKeyView.removeFromSuperview()
//        }

        let transition = ContainedViewLayoutTransition.animated(duration: duration, curve: .easeInOut)
        transition.updateAlpha(node: self, alpha: 1)
        transition.updateFrame(node: self, frame: originFrame)
        layer.animateScale(from: 0.2, to: 1, duration: duration)
    }

    func animateOut(to rect: CGRect, toNode: ASDisplayNode, completion: @escaping () -> Void) {
        let duration = 0.5

//        guard let transitionKeyView = self.keyTextNode.view.snapshotView(afterScreenUpdates: false) else { return }

//        self.keyTextNode.alpha = 0
//        let keyTransition = ContainedViewLayoutTransition.animated(duration: duration * 1.2, curve: .spring)

//        self.view.addSubview(transitionKeyView)

//        transitionKeyView.frame = self.keyTextNode.frame
//        keyTransition.updateFrame(view: transitionKeyView, frame: rect) { _ in
//            transitionKeyView.removeFromSuperview()
//        }

        let transition = ContainedViewLayoutTransition.animated(duration: duration, curve: .easeInOut)
        transition.updateAlpha(node: self, alpha: 0)
        transition.updateFrame(node: self, frame: rect) { _ in
            completion()
        }
        
        layer.animateScale(from: 1, to: 0.2, duration: duration)
    }

    @objc func tapDismiss() {
        self.dismiss()
    }
}
