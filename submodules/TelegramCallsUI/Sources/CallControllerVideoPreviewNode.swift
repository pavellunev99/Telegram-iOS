import Foundation
import UIKit
import Display
import AsyncDisplayKit
import Postbox
import TelegramCore
import SwiftSignalKit
import AccountContext
import TelegramPresentationData
import SolidRoundedButtonNode
import PresentationDataUtils
import UIKitRuntimeUtils
import ReplayKit

final class CallControllerVideoPreviewController: ViewController {
    private var controllerNode: CallControllerVideoPreviewNode {
        return self.displayNode as! CallControllerVideoPreviewNode
    }

    private let sharedContext: SharedAccountContext

    private var animatedIn = false

    private let cameraNode: PreviewVideoNode
    private let shareCamera: (ASDisplayNode, Bool) -> Void
    private let switchCamera: () -> Void
    private let inFromRect: CGRect
    private let previewRect: CGRect?

    private var presentationDataDisposable: Disposable?

    init(sharedContext: SharedAccountContext, cameraNode: PreviewVideoNode, inFromRect: CGRect, previewRect: CGRect?, shareCamera: @escaping (ASDisplayNode, Bool) -> Void, switchCamera: @escaping () -> Void) {
        self.sharedContext = sharedContext
        self.cameraNode = cameraNode
        self.shareCamera = shareCamera
        self.switchCamera = switchCamera
        self.inFromRect = inFromRect
        self.previewRect = previewRect

        super.init(navigationBarPresentationData: nil)

        self.statusBar.statusBarStyle = .Ignore

        self.blocksBackgroundWhenInOverlay = true

        self.presentationDataDisposable = (sharedContext.presentationData
        |> deliverOnMainQueue).start(next: { [weak self] presentationData in
            if let strongSelf = self {
                strongSelf.controllerNode.updatePresentationData(presentationData)
            }
        })

        self.statusBar.statusBarStyle = .Ignore
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.presentationDataDisposable?.dispose()
    }

    override public func loadDisplayNode() {
        self.displayNode = CallControllerVideoPreviewNode(controller: self, sharedContext: self.sharedContext, cameraNode: self.cameraNode, previewRect: previewRect)
        self.controllerNode.shareCamera = { [weak self] unmuted in
            if let strongSelf = self {
                strongSelf.shareCamera(strongSelf.cameraNode, unmuted)
                strongSelf.controllerNode.animateOut(true)
            }
        }
        self.controllerNode.switchCamera = { [weak self] in
            self?.switchCamera()
            self?.cameraNode.flip(withBackground: false)
        }
        self.controllerNode.dismiss = { [weak self] in
            self?.presentingViewController?.dismiss(animated: false, completion: nil)
        }
        self.controllerNode.cancel = { [weak self] in
            self?.dismiss()
        }
    }

    override public func loadView() {
        super.loadView()
    }

    override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        if !self.animatedIn {
            self.animatedIn = true
            self.controllerNode.animateIn(fromRect: inFromRect)
        }
    }

    override public func dismiss(completion: (() -> Void)? = nil) {
        self.controllerNode.animateOut(false, completion: completion)
    }

    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)

        self.controllerNode.containerLayoutUpdated(layout, navigationBarHeight: self.navigationLayout(layout: layout).navigationFrame.maxY, transition: transition)
    }
}

private class CallControllerVideoPreviewNode: ViewControllerTracingNode {
    private weak var controller: CallControllerVideoPreviewController?
    private let sharedContext: SharedAccountContext
    private var presentationData: PresentationData

    private let cameraNode: PreviewVideoNode
    private let contentContainerNode: ASDisplayNode
    private let titleNode: ASTextNode
    private let previewContainerNode: ASDisplayNode
    private let doneButton: SolidRoundedButtonNode
    private var broadcastPickerView: UIView?
    private let cancelButton: HighlightableButtonNode

    private let placeholderTextNode: ImmediateTextNode
    private let placeholderIconNode: ASImageNode

    private let dimNode: ASDisplayNode

    private var wheelNode: WheelControlNode
    private var selectedTabIndex: Int = 1
    private var containerLayout: (ContainerViewLayout, CGFloat)?

    private var applicationStateDisposable: Disposable?

    private let hapticFeedback = HapticFeedback()

    private let readyDisposable = MetaDisposable()

    var shareCamera: ((Bool) -> Void)?
    var switchCamera: (() -> Void)?
    var dismiss: (() -> Void)?
    var cancel: (() -> Void)?

    var previewRect: CGRect?

    init(controller: CallControllerVideoPreviewController, sharedContext: SharedAccountContext, cameraNode: PreviewVideoNode, previewRect: CGRect?) {
        self.controller = controller
        self.sharedContext = sharedContext
        self.presentationData = sharedContext.currentPresentationData.with { $0 }
        self.previewRect = previewRect

        self.cameraNode = cameraNode

        self.dimNode = ASDisplayNode()
        self.dimNode.backgroundColor = UIColor(white: 0.0, alpha: 0.5)

        self.contentContainerNode = ASDisplayNode()
        self.contentContainerNode.isOpaque = false

        let title =  self.presentationData.strings.VoiceChat_VideoPreviewTitle

        self.titleNode = ASTextNode()
        self.titleNode.attributedText = NSAttributedString(string: title, font: Font.bold(17.0), textColor: UIColor(rgb: 0xffffff))

        self.doneButton = SolidRoundedButtonNode(theme: SolidRoundedButtonTheme(backgroundColor: UIColor(rgb: 0xffffff), foregroundColor: UIColor(rgb: 0x4f5352)), font: .bold, height: 48.0, cornerRadius: 10.0, gloss: false)
        self.doneButton.title = self.presentationData.strings.VoiceChat_VideoPreviewContinue

        if #available(iOS 12.0, *) {
            let broadcastPickerView = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 50, height: 52.0))
            broadcastPickerView.alpha = 0.02
            broadcastPickerView.isHidden = true
            broadcastPickerView.preferredExtension = "\(self.sharedContext.applicationBindings.appBundleId).BroadcastUpload"
            broadcastPickerView.showsMicrophoneButton = false
            self.broadcastPickerView = broadcastPickerView
        }

        self.cancelButton = HighlightableButtonNode()
        self.cancelButton.setAttributedTitle(NSAttributedString(string: self.presentationData.strings.Common_Cancel, font: Font.regular(17.0), textColor: UIColor(rgb: 0xffffff)), for: [])

        self.previewContainerNode = ASDisplayNode()
        self.previewContainerNode.backgroundColor = .black

        self.placeholderTextNode = ImmediateTextNode()
        self.placeholderTextNode.alpha = 0.0
        self.placeholderTextNode.maximumNumberOfLines = 3
        self.placeholderTextNode.textAlignment = .center

        self.placeholderIconNode = ASImageNode()
        self.placeholderIconNode.alpha = 0.0
        self.placeholderIconNode.contentMode = .scaleAspectFit
        self.placeholderIconNode.displaysAsynchronously = false

        self.wheelNode = WheelControlNode(items: [WheelControlNode.Item(title: UIDevice.current.model == "iPad" ? self.presentationData.strings.VoiceChat_VideoPreviewTabletScreen : self.presentationData.strings.VoiceChat_VideoPreviewPhoneScreen), WheelControlNode.Item(title: self.presentationData.strings.VoiceChat_VideoPreviewFrontCamera), WheelControlNode.Item(title: self.presentationData.strings.VoiceChat_VideoPreviewBackCamera)], selectedIndex: self.selectedTabIndex)

        super.init()

        self.backgroundColor = nil
        self.isOpaque = false

        self.dimNode.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(self.dimTapGesture(_:))))
        self.addSubnode(self.dimNode)

        self.addSubnode(self.previewContainerNode)
        self.previewContainerNode.addSubnode(self.cameraNode)

        self.addSubnode(self.contentContainerNode)

        self.contentContainerNode.addSubnode(self.titleNode)
        self.contentContainerNode.addSubnode(self.doneButton)
        if let broadcastPickerView = self.broadcastPickerView {
            self.contentContainerNode.view.addSubview(broadcastPickerView)
        }
        self.contentContainerNode.addSubnode(self.cancelButton)

        self.contentContainerNode.addSubnode(self.placeholderIconNode)
        self.contentContainerNode.addSubnode(self.placeholderTextNode)

        self.contentContainerNode.addSubnode(self.wheelNode)

        self.wheelNode.selectedIndexChanged = { [weak self] index in
            if let strongSelf = self {
                if (index == 1 && strongSelf.selectedTabIndex == 2) || (index == 2 && strongSelf.selectedTabIndex == 1) {
                    strongSelf.switchCamera?()
                }
                if index == 0 && [1, 2].contains(strongSelf.selectedTabIndex) {
                    strongSelf.broadcastPickerView?.isHidden = false
                    strongSelf.cameraNode.updateIsBlurred(isBlurred: true, light: false, animated: true)
                    let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .easeInOut)
                    transition.updateAlpha(node: strongSelf.placeholderTextNode, alpha: 1.0)
                    transition.updateAlpha(node: strongSelf.placeholderIconNode, alpha: 1.0)
                } else if [1, 2].contains(index) && strongSelf.selectedTabIndex == 0 {
                    strongSelf.broadcastPickerView?.isHidden = true
                    strongSelf.cameraNode.updateIsBlurred(isBlurred: false, light: false, animated: true)
                    let transition = ContainedViewLayoutTransition.animated(duration: 0.3, curve: .easeInOut)
                    transition.updateAlpha(node: strongSelf.placeholderTextNode, alpha: 0.0)
                    transition.updateAlpha(node: strongSelf.placeholderIconNode, alpha: 0.0)
                }
                strongSelf.selectedTabIndex = index
            }
        }

        self.doneButton.pressed = { [weak self] in
            if let strongSelf = self {
                strongSelf.shareCamera?(true)
            }
        }

        self.cancelButton.addTarget(self, action: #selector(self.cancelPressed), forControlEvents: .touchUpInside)

        self.readyDisposable.set(self.cameraNode.ready.start(next: { _ in }))
    }

    deinit {
        self.readyDisposable.dispose()
        self.applicationStateDisposable?.dispose()
    }

    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
    }

    override func didLoad() {
        super.didLoad()

        let leftSwipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(self.leftSwipeGesture))
        leftSwipeGestureRecognizer.direction = .left
        let rightSwipeGestureRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(self.rightSwipeGesture))
        rightSwipeGestureRecognizer.direction = .right

        self.view.addGestureRecognizer(leftSwipeGestureRecognizer)
        self.view.addGestureRecognizer(rightSwipeGestureRecognizer)
    }

    @objc func leftSwipeGesture() {
        if self.selectedTabIndex < 2 {
            self.wheelNode.setSelectedIndex(self.selectedTabIndex + 1, animated: true)
            self.wheelNode.selectedIndexChanged(self.wheelNode.selectedIndex)
        }
    }

    @objc func rightSwipeGesture() {
        if self.selectedTabIndex > 0 {
            self.wheelNode.setSelectedIndex(self.selectedTabIndex - 1, animated: true)
            self.wheelNode.selectedIndexChanged(self.wheelNode.selectedIndex)
        }
    }

    @objc func cancelPressed() {
        self.cancel?()
    }

    @objc func dimTapGesture(_ recognizer: UITapGestureRecognizer) {
        if case .ended = recognizer.state {
            self.cancel?()
        }
    }

    func animateIn(fromRect: CGRect) {
        self.dimNode.layer.animateAlpha(from: 0.0, to: 1.0, duration: 0.4)

        let maskLayer = CAShapeLayer()
        maskLayer.frame = fromRect

        let path = CGMutablePath()
        path.addEllipse(in: CGRect(origin: CGPoint(), size: fromRect.size))
        maskLayer.path = path

        self.layer.mask = maskLayer

        let topLeft = CGPoint(x: 0.0, y: 0.0)
        let topRight = CGPoint(x: self.bounds.width, y: 0.0)
        let bottomLeft = CGPoint(x: 0.0, y: self.bounds.height)
        let bottomRight = CGPoint(x: self.bounds.width, y: self.bounds.height)

        func distance(_ v1: CGPoint, _ v2: CGPoint) -> CGFloat {
            let dx = v1.x - v2.x
            let dy = v1.y - v2.y
            return sqrt(dx * dx + dy * dy)
        }

        var maxRadius = distance(fromRect.center, topLeft)
        maxRadius = max(maxRadius, distance(fromRect.center, topRight))
        maxRadius = max(maxRadius, distance(fromRect.center, bottomLeft))
        maxRadius = max(maxRadius, distance(fromRect.center, bottomRight))
        maxRadius = ceil(maxRadius)

        let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .easeInOut)
        transition.updateTransformScale(layer: maskLayer, scale: maxRadius * 2.0 / fromRect.width, completion: { [weak self] _ in
            self?.layer.mask = nil
        })
        self.alpha = 0
        transition.updateAlpha(layer: self.layer, alpha: 1)

        self.applicationStateDisposable = (self.sharedContext.applicationBindings.applicationIsActive
        |> filter { !$0 }
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            strongSelf.controller?.dismiss()
        })
    }

    func animateOut(_ cameraShared: Bool = false, completion: (() -> Void)? = nil) {
        var dimCompleted = false
        var offsetCompleted = false

        let internalCompletion: () -> Void = { [weak self] in
            if let strongSelf = self, dimCompleted && offsetCompleted {
                strongSelf.dismiss?()
            }
            completion?()
        }

        self.dimNode.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { _ in
            dimCompleted = true
            internalCompletion()
        })

        if cameraShared, let previewRect = self.previewRect {
            let scale = max(previewRect.width / self.frame.width, previewRect.height / self.frame.height) * 1.0
            let w = previewRect.width / scale
            let h = previewRect.height / scale
            let x = self.frame.center.x * 0.1 + previewRect.center.x * 0.9
            let y = self.frame.center.y * 0.1 + previewRect.center.y * 0.9

            self.layer.animateFrame(from: self.frame, to: CGRect(origin: CGPoint(x: x - w / 2.0, y: y - h / 2.0), size: CGSize(width: w, height: h)), duration: 0.4, removeOnCompletion: false)

            self.doneButton.layer.animateAlpha(from: self.doneButton.alpha, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.cancelButton.layer.animateAlpha(from: self.cancelButton.alpha, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.wheelNode.layer.animateAlpha(from: self.wheelNode.alpha, to: 0.0, duration: 0.2, removeOnCompletion: false)
            self.titleNode.layer.animateAlpha(from: self.titleNode.alpha, to: 0.0, duration: 0.2, removeOnCompletion: false)

            self.layer.animateAlpha(from: self.alpha, to: 0.3, duration: 0.4, removeOnCompletion: false)

            let transition = ContainedViewLayoutTransition.animated(duration: 0.4, curve: .spring)
            transition.updateCornerRadius(layer: self.layer, cornerRadius: 14.0)

            self.clipsToBounds = true
            self.layer.animateScale(from: 1.0, to: scale * 1.4, duration: 0.4, removeOnCompletion: false) { _ in
                self.alpha = 0.0
                offsetCompleted = true
                internalCompletion()
            }
            internalCompletion()
        } else {
            let offset = self.bounds.size.height - self.contentContainerNode.frame.minY
            let dimPosition = self.dimNode.layer.position
            self.dimNode.layer.animatePosition(from: dimPosition, to: CGPoint(x: dimPosition.x, y: dimPosition.y - offset), duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false)
            self.layer.animateBoundsOriginYAdditive(from: 0.0, to: -offset, duration: 0.3, timingFunction: kCAMediaTimingFunctionSpring, removeOnCompletion: false, completion: { _ in
                offsetCompleted = true
                internalCompletion()
            })
        }
    }

    func containerLayoutUpdated(_ layout: ContainerViewLayout, navigationBarHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        self.containerLayout = (layout, navigationBarHeight)

        let isLandscape: Bool
        if layout.size.width > layout.size.height {
            isLandscape = true
        } else {
            isLandscape = false
        }
        let isTablet: Bool
        if case .regular = layout.metrics.widthClass {
            isTablet = true
        } else {
            isTablet = false
        }

        var insets = layout.insets(options: [.statusBar])
        insets.top = max(10.0, insets.top)

        let contentSize = CGSize(width: layout.size.width, height: layout.size.height - insets.top)
        let sideInset = floor((layout.size.width - contentSize.width) / 2.0)
        let contentFrame = CGRect(origin: CGPoint(x: sideInset, y: insets.top), size: contentSize)

        let titleSize = self.titleNode.measure(CGSize(width: contentFrame.width, height: .greatestFiniteMagnitude))
        let titleFrame = CGRect(origin: CGPoint(x: floor((contentFrame.width - titleSize.width) / 2.0), y: 20.0), size: titleSize)
        transition.updateFrame(node: self.titleNode, frame: titleFrame)

        let previewSize = layout.size
        let previewFrame = CGRect(origin: CGPoint(), size: previewSize)

        transition.updateFrame(node: self.dimNode, frame: CGRect(origin: CGPoint(), size: layout.size))
        transition.updateFrame(node: self.previewContainerNode, frame: previewFrame)

        let cancelButtonSize = self.cancelButton.measure(CGSize(width: (previewFrame.width - titleSize.width) / 2.0, height: .greatestFiniteMagnitude))
        let cancelButtonFrame = CGRect(origin: CGPoint(x: previewFrame.minX + 17.0, y: 20.0), size: cancelButtonSize)
        transition.updateFrame(node: self.cancelButton, frame: cancelButtonFrame)

        self.cameraNode.frame = previewFrame
        self.cameraNode.updateLayout(size: previewSize, layoutMode: isLandscape ? .fillHorizontal : .fillVertical, transition: .immediate)

        self.placeholderTextNode.attributedText = NSAttributedString(string: presentationData.strings.VoiceChat_VideoPreviewShareScreenInfo, font: Font.semibold(16.0), textColor: .white)
        self.placeholderIconNode.image = generateTintedImage(image: UIImage(bundleImageName: isTablet ? "Call/ScreenShareTablet" : "Call/ScreenSharePhone"), color: .white)

        let placeholderTextSize = self.placeholderTextNode.updateLayout(CGSize(width: previewSize.width - 80.0, height: 100.0))
        transition.updateFrame(node: self.placeholderTextNode, frame: CGRect(origin: CGPoint(x: floor((previewSize.width - placeholderTextSize.width) / 2.0), y: floorToScreenPixels(previewSize.height / 2.0) + 10.0), size: placeholderTextSize))
        if let imageSize = self.placeholderIconNode.image?.size {
            transition.updateFrame(node: self.placeholderIconNode, frame: CGRect(origin: CGPoint(x: floor((previewSize.width - imageSize.width) / 2.0), y: floorToScreenPixels(previewSize.height / 2.0) - imageSize.height - 8.0), size: imageSize))
        }

        let buttonInset: CGFloat = 16.0
        let buttonMaxWidth: CGFloat = 360.0

        let buttonWidth = min(buttonMaxWidth, contentFrame.width - buttonInset * 2.0)
        let doneButtonHeight = self.doneButton.updateLayout(width: buttonWidth, transition: transition)
        transition.updateFrame(node: self.doneButton, frame: CGRect(x: floorToScreenPixels((contentFrame.width - buttonWidth) / 2.0), y: contentFrame.maxY - doneButtonHeight - buttonInset - navigationBarHeight, width: buttonWidth, height: doneButtonHeight))
        self.broadcastPickerView?.frame = self.doneButton.frame

        let wheelFrame = CGRect(origin: CGPoint(x: 16.0 + contentFrame.minX, y: contentFrame.maxY - doneButtonHeight - buttonInset - 36.0 - 20.0 - navigationBarHeight), size: CGSize(width: contentFrame.width - 32.0, height: 36.0))
        self.wheelNode.updateLayout(size: wheelFrame.size, transition: transition)
        transition.updateFrame(node: self.wheelNode, frame: wheelFrame)

        transition.updateFrame(node: self.contentContainerNode, frame: contentFrame)
    }
}

private let textFont = Font.with(size: 14.0, design: .camera, weight: .regular)
private let selectedTextFont = Font.with(size: 14.0, design: .camera, weight: .semibold)

private class WheelControlNode: ASDisplayNode, UIGestureRecognizerDelegate {
    struct Item: Equatable {
        public let title: String

        public init(title: String) {
            self.title = title
        }
    }

    private let maskNode: ASDisplayNode
    private let containerNode: ASDisplayNode
    private var itemNodes: [HighlightTrackingButtonNode]

    private var validLayout: CGSize?

    private var _items: [Item]
    private var _selectedIndex: Int = 0

    public var selectedIndex: Int {
        get {
            return self._selectedIndex
        }
        set {
            guard newValue != self._selectedIndex else {
                return
            }
            self._selectedIndex = newValue
            if let size = self.validLayout {
                self.updateLayout(size: size, transition: .immediate)
            }
        }
    }

    public func setSelectedIndex(_ index: Int, animated: Bool) {
        guard index != self._selectedIndex else {
            return
        }
        self._selectedIndex = index
        if let size = self.validLayout {
            self.updateLayout(size: size, transition: .animated(duration: 0.2, curve: .easeInOut))
        }
    }

    public var selectedIndexChanged: (Int) -> Void = { _ in }

    public init(items: [Item], selectedIndex: Int) {
        self._items = items
        self._selectedIndex = selectedIndex

        self.maskNode = ASDisplayNode()
        self.maskNode.setLayerBlock({
            let maskLayer = CAGradientLayer()
            maskLayer.colors = [UIColor.clear.cgColor, UIColor.white.cgColor, UIColor.white.cgColor, UIColor.clear.cgColor]
            maskLayer.locations = [0.0, 0.15, 0.85, 1.0]
            maskLayer.startPoint = CGPoint(x: 0.0, y: 0.0)
            maskLayer.endPoint = CGPoint(x: 1.0, y: 0.0)
            return maskLayer
        })
        self.containerNode = ASDisplayNode()

        self.itemNodes = items.map { item in
            let itemNode = HighlightTrackingButtonNode()
            itemNode.contentEdgeInsets = UIEdgeInsets(top: 0.0, left: 8.0, bottom: 0.0, right: 8.0)
            itemNode.titleNode.maximumNumberOfLines = 1
            itemNode.titleNode.truncationMode = .byTruncatingTail
            itemNode.accessibilityLabel = item.title
            itemNode.accessibilityTraits = [.button]
            itemNode.hitTestSlop = UIEdgeInsets(top: -10.0, left: -5.0, bottom: -10.0, right: -5.0)
            itemNode.setTitle(item.title.uppercased(), with: textFont, with: .white, for: .normal)
            itemNode.titleNode.shadowColor = UIColor.black.cgColor
            itemNode.titleNode.shadowOffset = CGSize()
            itemNode.titleNode.layer.shadowRadius = 2.0
            itemNode.titleNode.layer.shadowOpacity = 0.3
            itemNode.titleNode.layer.masksToBounds = false
            itemNode.titleNode.layer.shouldRasterize = true
            itemNode.titleNode.layer.rasterizationScale = UIScreen.main.scale
            return itemNode
        }

        super.init()

        self.clipsToBounds = true

        self.addSubnode(self.containerNode)

        self.itemNodes.forEach(self.containerNode.addSubnode(_:))
        self.setupButtons()
    }

    override func didLoad() {
        super.didLoad()

        self.view.layer.mask = self.maskNode.layer

        self.view.disablesInteractiveTransitionGestureRecognizer = true
    }

    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        self.validLayout = size

        let bounds = CGRect(origin: CGPoint(), size: size)

        transition.updateFrame(node: self.maskNode, frame: bounds)

        let spacing: CGFloat = 15.0
        if !self.itemNodes.isEmpty {
            var leftOffset: CGFloat = 0.0
            var selectedItemNode: ASDisplayNode?
            for i in 0 ..< self.itemNodes.count {
                let itemNode = self.itemNodes[i]
                let itemSize = itemNode.measure(size)
                transition.updateFrame(node: itemNode, frame: CGRect(origin: CGPoint(x: leftOffset, y: (size.height - itemSize.height) / 2.0), size: itemSize))

                leftOffset += itemSize.width + spacing

                let isSelected = self.selectedIndex == i
                if isSelected {
                    selectedItemNode = itemNode
                }
                if itemNode.isSelected != isSelected {
                    itemNode.isSelected = isSelected
                    let title = itemNode.attributedTitle(for: .normal)?.string ?? ""
                    itemNode.setTitle(title, with: isSelected ? selectedTextFont : textFont, with: .white, for: .normal)
                    if isSelected {
                        itemNode.accessibilityTraits.insert(.selected)
                    } else {
                        itemNode.accessibilityTraits.remove(.selected)
                    }
                }
            }

            let totalWidth = leftOffset - spacing
            if let selectedItemNode = selectedItemNode {
                let itemCenter = selectedItemNode.frame.center
                transition.updateFrame(node: self.containerNode, frame: CGRect(x: bounds.width / 2.0 - itemCenter.x, y: 0.0, width: totalWidth, height: bounds.height))

                for i in 0 ..< self.itemNodes.count {
                    let itemNode = self.itemNodes[i]
                    let convertedBounds = itemNode.view.convert(itemNode.bounds, to: self.view)
                    let position = convertedBounds.center
                    let offset = position.x - bounds.width / 2.0
                    let angle = abs(offset / bounds.width * 0.99)
                    let sign: CGFloat = offset > 0 ? 1.0 : -1.0

                    var transform = CATransform3DMakeTranslation(-22.0 * angle * angle * sign, 0.0, 0.0)
                    transform = CATransform3DRotate(transform, angle, 0.0, sign, 0.0)
                    transition.animateView {
                        itemNode.transform = transform
                    }
                }
            }
        }
    }

    private func setupButtons() {
        for i in 0 ..< self.itemNodes.count {
            let itemNode = self.itemNodes[i]
            itemNode.addTarget(self, action: #selector(self.buttonPressed(_:)), forControlEvents: .touchUpInside)
        }
    }

    @objc private func buttonPressed(_ button: HighlightTrackingButtonNode) {
        guard let index = self.itemNodes.firstIndex(of: button) else {
            return
        }

        self._selectedIndex = index
        self.selectedIndexChanged(index)
        if let size = self.validLayout {
            self.updateLayout(size: size, transition: .animated(duration: 0.2, curve: .slide))
        }
    }
}
