import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Accelerate
import Dispatch

final class CallControllerBackgroundNode: ASDisplayNode {

    public final class CloneNode: ASImageNode {
        private weak var parentNode: CallControllerBackgroundNode?
        private var index: SparseBag<Weak<CloneNode>>.Index?

        public init(parentNode: CallControllerBackgroundNode) {
            self.parentNode = parentNode

            super.init()

            self.displaysAsynchronously = false

            self.index = parentNode.cloneNodes.add(Weak<CloneNode>(self))
            self.image = parentNode.dimmedImage
        }

        deinit {
            if let parentNode = self.parentNode, let index = self.index {
                parentNode.cloneNodes.remove(index)
            }
        }
    }

    enum ContentState {
        case pending
        case active
        case weakSignal
    }

    private(set) var currentState: ContentState?
    private(set) var isAnimating: Bool = false

    private var colors: [UIColor] {
        guard let currentState = currentState else { return [] }
        switch currentState {
        case .pending:
            return [
                UIColor(red: 0.45, green: 0.38, blue: 0.85, alpha: 1.0),
                UIColor(red: 0.67, green: 0.40, blue: 0.83, alpha: 1.0),
                UIColor(red: 0.38, green: 0.42, blue: 0.83, alpha: 1.0),
                UIColor(red: 0.32, green: 0.58, blue: 0.84, alpha: 1.0)
            ]
        case .active:
            return [
                UIColor(red: 0.24, green: 0.61, blue: 0.56, alpha: 1.0),
                UIColor(red: 0.73, green: 0.75, blue: 0.36, alpha: 1.0),
                UIColor(red: 0.22, green: 0.55, blue: 0.44, alpha: 1.0),
                UIColor(red: 0.33, green: 0.65, blue: 0.87, alpha: 1.0)
            ]
        case .weakSignal:
            return [
                UIColor(red: 1.0, green: 0.49, blue: 0.27, alpha: 1.0),
                UIColor(red: 0.79, green: 0.29, blue: 0.53, alpha: 1.0),
                UIColor(red: 0.96, green: 0.6, blue: 0.18, alpha: 1.0),
                UIColor(red: 0.72, green: 0.27, blue: 0.6, alpha: 1.0)
            ]
        }
    }

    private static let basePositions: [CGPoint] = [
        CGPoint(x: 0.80, y: 0.10),
        CGPoint(x: 0.60, y: 0.20),
        CGPoint(x: 0.35, y: 0.25),
        CGPoint(x: 0.25, y: 0.60),
        CGPoint(x: 0.20, y: 0.90),
        CGPoint(x: 0.40, y: 0.80),
        CGPoint(x: 0.65, y: 0.75),
        CGPoint(x: 0.75, y: 0.40)
    ]

    public static func generatePreview(size: CGSize, colors: [UIColor]) -> UIImage {
        let positions = gatherPositions(shiftArray(array: CallControllerBackgroundNode.basePositions, offset: 0))
        return generateGradient(size: size, colors: colors, positions: positions).0
    }

    private var phase: Int = 0

    private var backgroundImageHash: String?

    public let contentView: UIImageView
    private var validPhase: Int?
    private var invalidated: Bool = false
    private var timer: SwiftSignalKit.Timer?

    private var dimmedImageParams: (size: CGSize, colors: [UIColor], positions: [CGPoint])?
    private var _dimmedImage: UIImage?
    private var dimmedImage: UIImage? {
        if let current = self._dimmedImage {
            return current
        } else if let (size, colors, positions) = self.dimmedImageParams {
            self._dimmedImage = generateGradient(size: size, colors: colors, positions: positions, adjustSaturation: self.saturation).0
            return self._dimmedImage
        } else {
            return nil
        }
    }

    private var validLayout: CGSize?
    private let cloneNodes = SparseBag<Weak<CloneNode>>()

    private let useSharedAnimationPhase: Bool
    static var sharedPhase: Int = 0

    private let saturation: CGFloat

    private var patternOverlayLayer: GradientBackgroundPatternOverlayLayer?

    public init(useSharedAnimationPhase: Bool = false, adjustSaturation: Bool = true) {
        self.useSharedAnimationPhase = useSharedAnimationPhase
        self.saturation = adjustSaturation ? 1.7 : 1.0
        self.contentView = UIImageView()

        super.init()

        self.view.addSubview(self.contentView)
        self.displaysAsynchronously = true

        if useSharedAnimationPhase {
            self.phase = CallControllerBackgroundNode.sharedPhase
        } else {
            self.phase = 0
        }
    }

    deinit {
    }

    public func setPatternOverlay(layer: GradientBackgroundPatternOverlayLayer?) {
        if self.patternOverlayLayer === layer {
            return
        }

        if let patternOverlayLayer = self.patternOverlayLayer {
            if patternOverlayLayer.superlayer == self.layer {
                patternOverlayLayer.removeFromSuperlayer()
            }
            self.patternOverlayLayer = nil
        }

        self.patternOverlayLayer = layer

        if let patternOverlayLayer = self.patternOverlayLayer {
            self.layer.addSublayer(patternOverlayLayer)

            patternOverlayLayer.isAnimating = self.isAnimating

            if let image = self.contentView.image, let backgroundImageHash = self.backgroundImageHash, self.contentView.bounds.width > 1.0, self.contentView.bounds.height > 1.0 {
                patternOverlayLayer.updateCompositionData(size: self.contentView.bounds.size, backgroundImage: image, backgroundImageHash: backgroundImageHash)
            }
        }
    }

    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition, extendAnimation: Bool, backwards: Bool, completion: @escaping () -> Void) {
        let sizeUpdated = self.validLayout != size
        self.validLayout = size

        let imageSize = size.fitted(CGSize(width: 80.0, height: 80.0)).integralFloor

        let positions = gatherPositions(shiftArray(array: CallControllerBackgroundNode.basePositions, offset: self.phase % 8))

//        let previousImage = self.contentView.image
//        let previousSize = self.contentView.bounds.size

        if let validPhase = self.validPhase {
            if validPhase != self.phase || self.invalidated {
                self.validPhase = self.phase
                self.invalidated = false

                var steps: [[CGPoint]] = []
                if backwards {
                    let phaseCount = extendAnimation ? 6 : 1
                    self.phase = (self.phase + phaseCount) % 8
                    self.validPhase = self.phase

                    var stepPhase = self.phase - phaseCount
                    if stepPhase < 0 {
                        stepPhase = 8 + stepPhase
                    }
                    for _ in 0 ... phaseCount {
                        steps.append(gatherPositions(shiftArray(array: CallControllerBackgroundNode.basePositions, offset: stepPhase)))
                        stepPhase = (stepPhase + 1) % 8
                    }
                } else if extendAnimation {
                    let phaseCount = 4
                    var stepPhase = (self.phase + phaseCount) % 8
                    for _ in 0 ... phaseCount {
                        steps.append(gatherPositions(shiftArray(array: CallControllerBackgroundNode.basePositions, offset: stepPhase)))
                        stepPhase = stepPhase - 1
                        if stepPhase < 0 {
                            stepPhase = 7
                        }
                    }
                } else {
                    steps.append(gatherPositions(shiftArray(array: CallControllerBackgroundNode.basePositions, offset: validPhase % 8)))
                    steps.append(positions)
                }

                if case let .animated(duration, curve) = transition, duration > 0.001 {
                    var images: [(UIImage, String)] = []

                    var dimmedImages: [UIImage] = []
                    let needDimmedImages = !self.cloneNodes.isEmpty

                    let stepCount = steps.count - 1

                    let fps: Double = extendAnimation ? 60 : 30
                    let maxFrame = Int(duration * fps)
                    let framesPerAnyStep = maxFrame / stepCount

                    for frameIndex in 0 ..< maxFrame {
                        let t = curve.solve(at: CGFloat(frameIndex) / CGFloat(maxFrame - 1))
                        let globalStep = Int(t * CGFloat(maxFrame))
                        let stepIndex = min(stepCount - 1, globalStep / framesPerAnyStep)

                        let stepFrameIndex = globalStep - stepIndex * framesPerAnyStep
                        let stepFrames: Int
                        if stepIndex == stepCount - 1 {
                            stepFrames = maxFrame - framesPerAnyStep * (stepCount - 1)
                        } else {
                            stepFrames = framesPerAnyStep
                        }
                        let stepT = CGFloat(stepFrameIndex) / CGFloat(stepFrames - 1)

                        var morphedPositions: [CGPoint] = []
                        for i in 0 ..< steps[0].count {
                            morphedPositions.append(interpolatePoints(steps[stepIndex][i], steps[stepIndex + 1][i], at: stepT))
                        }

                        images.append(generateGradient(size: imageSize, colors: self.colors, positions: morphedPositions))
                        if needDimmedImages {
                            dimmedImages.append(generateGradient(size: imageSize, colors: self.colors, positions: morphedPositions, adjustSaturation: self.saturation).0)
                        }
                    }

                    self.dimmedImageParams = (imageSize, self.colors, gatherPositions(shiftArray(array: CallControllerBackgroundNode.basePositions, offset: self.phase % 8)))

                    Queue.mainQueue().async {

                        self.contentView.image = images[images.count - 1].0
                        self.backgroundImageHash = images[images.count - 1].1

                        let animation = CAKeyframeAnimation(keyPath: "contents")
                        animation.values = images.map { $0.0.cgImage! }
                        animation.duration = duration * UIView.animationDurationFactor()
                        if backwards || extendAnimation {
                            animation.calculationMode = .discrete
                        } else {
                            animation.calculationMode = .linear
                        }
                        animation.isRemovedOnCompletion = true
                        if extendAnimation && !backwards {
                            animation.fillMode = .backwards
                            animation.beginTime = self.contentView.layer.convertTime(CACurrentMediaTime(), from: nil) + 0.25
                        }


                        self.isAnimating = true
                        if let patternOverlayLayer = self.patternOverlayLayer {
                            patternOverlayLayer.isAnimating = true
                        }
                        animation.completion = { [weak self] value in
                            if let strongSelf = self, value {
                                strongSelf.isAnimating = false
                                if let patternOverlayLayer = strongSelf.patternOverlayLayer {
                                    patternOverlayLayer.isAnimating = false
                                }
                            }

                            completion()
                        }

                        self.contentView.layer.removeAnimation(forKey: "contents")
                        self.contentView.layer.add(animation, forKey: "contents")

                        if !self.cloneNodes.isEmpty {
                            let cloneAnimation = CAKeyframeAnimation(keyPath: "contents")
                            cloneAnimation.values = dimmedImages.map { $0.cgImage! }
                            cloneAnimation.duration = animation.duration
                            cloneAnimation.calculationMode = animation.calculationMode
                            cloneAnimation.isRemovedOnCompletion = animation.isRemovedOnCompletion
                            cloneAnimation.fillMode = animation.fillMode
                            cloneAnimation.beginTime = animation.beginTime

                            self._dimmedImage = dimmedImages.last

                            for cloneNode in self.cloneNodes {
                                if let value = cloneNode.value {
                                    value.image = dimmedImages.last

                                    value.layer.removeAnimation(forKey: "contents")
                                    value.layer.add(cloneAnimation, forKey: "contents")
                                }
                            }
                        }
                    }
                } else {
                    let (image, imageHash) = generateGradient(size: imageSize, colors: self.colors, positions: positions)
                    self.contentView.image = image
                    self.backgroundImageHash = imageHash

                    let dimmedImage = generateGradient(size: imageSize, colors: self.colors, positions: positions, adjustSaturation: self.saturation).0
                    self._dimmedImage = dimmedImage
                    self.dimmedImageParams = (imageSize, self.colors, positions)

                    for cloneNode in self.cloneNodes {
                        cloneNode.value?.image = dimmedImage
                    }

                    completion()
                }
            } else if sizeUpdated {
                let (image, imageHash) = generateGradient(size: imageSize, colors: self.colors, positions: positions)
                self.contentView.image = image
                self.backgroundImageHash = imageHash

                let dimmedImage = generateGradient(size: imageSize, colors: self.colors, positions: positions, adjustSaturation: self.saturation).0
                self.dimmedImageParams = (imageSize, self.colors, positions)

                for cloneNode in self.cloneNodes {
                    cloneNode.value?.image = dimmedImage
                }

                self.validPhase = self.phase

                completion()
            } else {
                completion()
            }
        } else if sizeUpdated {
            let (image, imageHash) = generateGradient(size: imageSize, colors: self.colors, positions: positions)
            self.contentView.image = image
            self.backgroundImageHash = imageHash

            let dimmedImage = generateGradient(size: imageSize, colors: self.colors, positions: positions, adjustSaturation: self.saturation).0
            self.dimmedImageParams = (imageSize, self.colors, positions)

            for cloneNode in self.cloneNodes {
                cloneNode.value?.image = dimmedImage
            }

            self.validPhase = self.phase

            completion()
        } else {
            completion()
        }

        transition.updateFrame(view: self.contentView, frame: CGRect(origin: CGPoint(), size: size))
    }

    func update(state: ContentState) {
        guard currentState != state else { return }

        self.currentState = state

        var updated = false

        for i in 0 ..< self.colors.count {
            if !self.colors[i].isEqual(colors[i]) {
                updated = true
                break
            }
        }

        if updated {
            self.invalidated = true
            if let size = self.validLayout {
                self.updateLayout(size: size, transition: .immediate, extendAnimation: false, backwards: false, completion: {})
            }
        }
    }

    func startAnimating() {
        if isAnimating == false {
            isAnimating = true
            
            self.timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
                self?._animateEvent()
            }, queue: Queue(name: "CallBackgroundQueue", qos: .userInteractive))
            
            self._animateEvent()
            self.timer?.start()
        }
    }

    func stopAnimating() {
        self.isAnimating = false
        self.contentView.layer.removeAnimation(forKey: "contents")
        self.timer?.invalidate()
        self.timer = nil
    }

    private func _animateEvent() {
        if self.phase == 0 {
            self.phase = 7
        } else {
            self.phase = self.phase - 1
        }
        if self.useSharedAnimationPhase {
            CallControllerBackgroundNode.sharedPhase = self.phase
        }
        if let size = self.validLayout {
            self.updateLayout(size: size, transition: .animated(duration: 1, curve: .linear), extendAnimation: false, backwards: false, completion: { })
        }
    }
}

private func shiftArray(array: [CGPoint], offset: Int) -> [CGPoint] {
    var newArray = array
    var offset = offset
    while offset > 0 {
        let element = newArray.removeFirst()
        newArray.append(element)
        offset -= 1
    }
    return newArray
}

private func gatherPositions(_ list: [CGPoint]) -> [CGPoint] {
    var result: [CGPoint] = []
    for i in 0 ..< list.count / 2 {
        result.append(list[i * 2])
    }
    return result
}

private func interpolateFloat(_ value1: CGFloat, _ value2: CGFloat, at factor: CGFloat) -> CGFloat {
    return value1 * (1.0 - factor) + value2 * factor
}

private func interpolatePoints(_ point1: CGPoint, _ point2: CGPoint, at factor: CGFloat) -> CGPoint {
    return CGPoint(x: interpolateFloat(point1.x, point2.x, at: factor), y: interpolateFloat(point1.y, point2.y, at: factor))
}

public func adjustSaturationInContext(context: DrawingContext, saturation: CGFloat) {
    var buffer = vImage_Buffer()
    buffer.data = context.bytes
    buffer.width = UInt(context.size.width * context.scale)
    buffer.height = UInt(context.size.height * context.scale)
    buffer.rowBytes = context.bytesPerRow

    let divisor: Int32 = 0x1000

    let rwgt: CGFloat = 0.3086
    let gwgt: CGFloat = 0.6094
    let bwgt: CGFloat = 0.0820

    let adjustSaturation = saturation

    let a = (1.0 - adjustSaturation) * rwgt + adjustSaturation
    let b = (1.0 - adjustSaturation) * rwgt
    let c = (1.0 - adjustSaturation) * rwgt
    let d = (1.0 - adjustSaturation) * gwgt
    let e = (1.0 - adjustSaturation) * gwgt + adjustSaturation
    let f = (1.0 - adjustSaturation) * gwgt
    let g = (1.0 - adjustSaturation) * bwgt
    let h = (1.0 - adjustSaturation) * bwgt
    let i = (1.0 - adjustSaturation) * bwgt + adjustSaturation

    let satMatrix: [CGFloat] = [
        a, b, c, 0,
        d, e, f, 0,
        g, h, i, 0,
        0, 0, 0, 1
    ]

    var matrix: [Int16] = satMatrix.map { value in
        return Int16(value * CGFloat(divisor))
    }

    vImageMatrixMultiply_ARGB8888(&buffer, &buffer, &matrix, divisor, nil, nil, vImage_Flags(kvImageDoNotTile))
}

private func generateGradient(size: CGSize, colors inputColors: [UIColor], positions: [CGPoint], adjustSaturation: CGFloat = 1.0) -> (UIImage, String) {
    let colors: [UIColor] = inputColors.count == 1 ? [inputColors[0], inputColors[0], inputColors[0]] : inputColors

    let width = Int(size.width)
    let height = Int(size.height)

    let rgbData = malloc(MemoryLayout<Float>.size * colors.count * 3)!
    defer {
        free(rgbData)
    }
    let rgb = rgbData.assumingMemoryBound(to: Float.self)
    for i in 0 ..< colors.count {
        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        colors[i].getRed(&r, green: &g, blue: &b, alpha: nil)

        rgb.advanced(by: i * 3 + 0).pointee = Float(r)
        rgb.advanced(by: i * 3 + 1).pointee = Float(g)
        rgb.advanced(by: i * 3 + 2).pointee = Float(b)
    }

    let positionData = malloc(MemoryLayout<Float>.size * positions.count * 2)!
    defer {
        free(positionData)
    }
    let positionFloats = positionData.assumingMemoryBound(to: Float.self)
    for i in 0 ..< positions.count {
        positionFloats.advanced(by: i * 2 + 0).pointee = Float(positions[i].x)
        positionFloats.advanced(by: i * 2 + 1).pointee = Float(1.0 - positions[i].y)
    }

    let context = DrawingContext(size: CGSize(width: CGFloat(width), height: CGFloat(height)), scale: 1.0, opaque: true, clear: false)!
    let imageBytes = context.bytes.assumingMemoryBound(to: UInt8.self)

    for y in 0 ..< height {
        let directPixelY = Float(y) / Float(height)
        let centerDistanceY = directPixelY - 0.5
        let centerDistanceY2 = centerDistanceY * centerDistanceY

        let lineBytes = imageBytes.advanced(by: context.bytesPerRow * y)
        for x in 0 ..< width {
            let directPixelX = Float(x) / Float(width)

            let centerDistanceX = directPixelX - 0.5
            let centerDistance = sqrt(centerDistanceX * centerDistanceX + centerDistanceY2)

            let swirlFactor = 0.35 * centerDistance
            let theta = swirlFactor * swirlFactor * 0.8 * 8.0
            let sinTheta = sin(theta)
            let cosTheta = cos(theta)

            let pixelX = max(0.0, min(1.0, 0.5 + centerDistanceX * cosTheta - centerDistanceY * sinTheta))
            let pixelY = max(0.0, min(1.0, 0.5 + centerDistanceX * sinTheta + centerDistanceY * cosTheta))

            var distanceSum: Float = 0.0

            var r: Float = 0.0
            var g: Float = 0.0
            var b: Float = 0.0

            for i in 0 ..< colors.count {
                let colorX = positionFloats[i * 2 + 0]
                let colorY = positionFloats[i * 2 + 1]

                let distanceX = pixelX - colorX
                let distanceY = pixelY - colorY

                var distance = max(0.0, 0.92 - sqrt(distanceX * distanceX + distanceY * distanceY))
                distance = distance * distance * distance
                distanceSum += distance

                r = r + distance * rgb[i * 3 + 0]
                g = g + distance * rgb[i * 3 + 1]
                b = b + distance * rgb[i * 3 + 2]
            }

            if distanceSum < 0.00001 {
                distanceSum = 0.00001
            }

            var pixelB = b / distanceSum * 255.0
            if pixelB > 255.0 {
                pixelB = 255.0
            }

            var pixelG = g / distanceSum * 255.0
            if pixelG > 255.0 {
                pixelG = 255.0
            }

            var pixelR = r / distanceSum * 255.0
            if pixelR > 255.0 {
                pixelR = 255.0
            }

            let pixelBytes = lineBytes.advanced(by: x * 4)
            pixelBytes.advanced(by: 0).pointee = UInt8(pixelB)
            pixelBytes.advanced(by: 1).pointee = UInt8(pixelG)
            pixelBytes.advanced(by: 2).pointee = UInt8(pixelR)
            pixelBytes.advanced(by: 3).pointee = 0xff
        }
    }

    if abs(adjustSaturation - 1.0) > .ulpOfOne {
        adjustSaturationInContext(context: context, saturation: adjustSaturation)
    }

    var hashString = ""
    hashString.append("\(size.width)x\(size.height)")
    for color in colors {
        hashString.append("_\(color.argb)")
    }
    for position in positions {
        hashString.append("_\(position.x):\(position.y)")
    }
    hashString.append("_\(adjustSaturation)")

    return (context.generateImage()!, hashString)
}

public protocol GradientBackgroundPatternOverlayLayer: CALayer {
    var isAnimating: Bool { get set }

    func updateCompositionData(size: CGSize, backgroundImage: UIImage, backgroundImageHash: String)
}
