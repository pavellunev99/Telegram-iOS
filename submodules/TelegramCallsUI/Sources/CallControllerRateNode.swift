import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Accelerate
import TelegramPresentationData
import AnimatedStickerNode
import TelegramAnimatedStickerNode

final class CallControllerRateNode: ASDisplayNode {
    private let strings: PresentationStrings
    private let apply: (Int) -> Void

    var rating: Int?

    private let backgroundNode: ASDisplayNode
    private let titleNode: ASTextNode
    private let descriptionNode: ASTextNode
    private var starContainerNode: ASDisplayNode
    private let starNodes: [ASButtonNode]
    private var rateCallAnimationNode: AnimatedStickerNode?

    private let disposable = MetaDisposable()

    private var validLayout: CGSize?

    init(strings: PresentationStrings, apply: @escaping (Int) -> Void) {

        self.backgroundNode = ASDisplayNode()

        self.strings = strings
        self.apply = apply

        self.titleNode = ASTextNode()
        self.titleNode.maximumNumberOfLines = 1

        self.descriptionNode = ASTextNode()
        self.descriptionNode.maximumNumberOfLines = 3

        self.starContainerNode = ASDisplayNode()

        var starNodes: [ASButtonNode] = []
        for _ in 0 ..< 5 {
            starNodes.append(ASButtonNode())
        }
        self.starNodes = starNodes

        super.init()

        self.addSubnode(self.backgroundNode)

        self.backgroundNode.clipsToBounds = true
        self.backgroundNode.cornerRadius = 20
        self.backgroundNode.backgroundColor = .white.withAlphaComponent(0.25)

        self.addSubnode(self.titleNode)

        self.addSubnode(self.descriptionNode)

        self.addSubnode(self.starContainerNode)

        for node in self.starNodes {
            node.addTarget(self, action: #selector(self.starPressed(_:)), forControlEvents: .touchDown)
            node.addTarget(self, action: #selector(self.starReleased(_:)), forControlEvents: .touchUpInside)
            self.starContainerNode.addSubnode(node)
        }

        self.titleNode.attributedText = NSAttributedString(string: self.strings.Call_RateCall, font: Font.semibold(16), textColor: .white, paragraphAlignment: .center)
        self.descriptionNode.attributedText = NSAttributedString(string: self.strings.Calls_RatingTitle, font: Font.regular(16), textColor: .white, paragraphAlignment: .center)

        for node in self.starNodes {
            node.setImage(generateTintedImage(image: UIImage(bundleImageName: "Call/Star"), color: .white), for: [])
            let highlighted = generateTintedImage(image: UIImage(bundleImageName: "Call/StarHighlighted"), color: .white)
            node.setImage(highlighted, for: [.selected])
            node.setImage(highlighted, for: [.selected, .highlighted])
        }

        if let size = self.validLayout {
            let _ = self.updateLayout(size: size, transition: .immediate)
        }
    }

    deinit {
        self.disposable.dispose()
    }

    override func didLoad() {
        super.didLoad()
        self.starContainerNode.view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(self.panGesture(_:))))
    }

    @objc func panGesture(_ gestureRecognizer: UIPanGestureRecognizer) {
        let location = gestureRecognizer.location(in: self.starContainerNode.view)
        var selectedNode: ASButtonNode?
        for node in self.starNodes {
            if node.frame.contains(location) {
                selectedNode = node
                break
            }
        }
        if let selectedNode = selectedNode {
            switch gestureRecognizer.state {
                case .began, .changed:
                    self.starPressed(selectedNode)
                case .ended:
                    self.starReleased(selectedNode)
                case .cancelled:
                    self.resetStars()
                default:
                    break
            }
        } else {
            self.resetStars()
        }
    }

    private func resetStars() {
        for i in 0 ..< self.starNodes.count {
            let node = self.starNodes[i]
            node.isSelected = false
        }
    }

    @objc func starPressed(_ sender: ASButtonNode) {
        if let index = self.starNodes.firstIndex(of: sender) {
            self.rating = index + 1
            for i in 0 ..< self.starNodes.count {
                let node = self.starNodes[i]
                node.isSelected = i <= index
            }
        }
    }

    @objc func starReleased(_ sender: ASButtonNode) {
        if let index = self.starNodes.firstIndex(of: sender) {
            self.rating = index + 1
            for i in 0 ..< self.starNodes.count {
                let node = self.starNodes[i]
                if i <= index {
                    node.isSelected = true
                    node.layer.animateScale(from: 1, to: 1.2, duration: 0.1) { _ in
                        node.layer.animateScale(from: 1.2, to: 1, duration: 0.1)
                    }
                } else {
                    node.isSelected = false
                }

                if i == index, index + 1 >= 4 {
                    self.rateCallAnimationNode = DefaultAnimatedStickerNodeImpl()
                    self.addSubnode(rateCallAnimationNode!)
                    self.rateCallAnimationNode?.setup(source: AnimatedStickerNodeLocalFileSource(name: "Stars"), width: 256, height: 256, playbackMode: .once, mode: .direct(cachePathPrefix: nil))
                    self.rateCallAnimationNode?.visibility = true

                    let animationSize = CGSize(width: 128, height: 128)
                    let convertedPoint = self.starContainerNode.convert(node.frame.origin, to: self)
                    let nodeRect = CGRect(origin: convertedPoint, size: node.frame.size)

                    self.rateCallAnimationNode?.frame = CGRect(origin: CGPoint(x: nodeRect.midX - animationSize.width / 2, y: nodeRect.midY - animationSize.height / 2), size: animationSize)
                    self.rateCallAnimationNode?.updateLayout(size: animationSize)
                    self.rateCallAnimationNode?.playOnce()
                }
            }

            if let rating = self.rating {
                Queue.mainQueue().after(1) {
                    self.apply(rating)
                }
            }
        }
    }

    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {
        var size = size
        size.width = min(size.width , 270.0)

        self.validLayout = size

        let insets = UIEdgeInsets(top: 20.0, left: 18.0, bottom: 20.0, right: 18.0)

        var origin: CGPoint = CGPoint(x: 0.0, y: 20.0)
        let titleSize = self.titleNode.measure(CGSize(width: size.width - 32.0, height: size.height))
        let descriptonSize = self.descriptionNode.measure(CGSize(width: size.width - 32.0, height: size.height))

        var contentWidth = titleSize.width
        contentWidth = max(contentWidth, 234.0)

        let resultWidth = contentWidth + insets.left + insets.right

        transition.updateFrame(node: self.titleNode, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((resultWidth - titleSize.width) / 2.0), y: origin.y), size: titleSize))
        origin.y += titleSize.height + 10.0

        transition.updateFrame(node: self.descriptionNode, frame: CGRect(origin: CGPoint(x: floorToScreenPixels((resultWidth - descriptonSize.width) / 2.0), y: origin.y), size: descriptonSize))
        origin.y += titleSize.height + 15.0

        let starSize = CGSize(width: 42.0, height: 38.0)
        let starsOrigin = floorToScreenPixels((resultWidth - starSize.width * 5.0) / 2.0)
        self.starContainerNode.frame = CGRect(origin: CGPoint(x: starsOrigin, y: origin.y), size: CGSize(width: starSize.width * CGFloat(self.starNodes.count), height: starSize.height))
        for i in 0 ..< self.starNodes.count {
            let node = self.starNodes[i]
            transition.updateFrame(node: node, frame: CGRect(x: starSize.width * CGFloat(i), y: 0.0, width: starSize.width, height: starSize.height))
        }
        origin.y += titleSize.height

        let resultSize = CGSize(width: resultWidth, height: titleSize.height + descriptonSize.height + 56.0 + insets.top + insets.bottom)
        transition.updateFrame(node: self.backgroundNode, frame: CGRect(origin: CGPoint(), size: resultSize))

        return resultSize
    }
}
