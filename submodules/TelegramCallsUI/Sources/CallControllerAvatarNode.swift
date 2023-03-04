import Foundation
import UIKit
import Display
import AsyncDisplayKit
import SwiftSignalKit
import Accelerate
import AudioBlob

final class CallControllerAvatarNode: ASDisplayNode {

    let imageNode: TransformImageNode
    let speakingAudioLevelView: VoiceBlobView

    override init() {
        self.speakingAudioLevelView = VoiceBlobView(
            frame: CGRect(),
            maxLevel: 1.5,
            smallBlobRange: (0, 0),
            mediumBlobRange: (0.69, 0.87),
            bigBlobRange: (0.71, 1.0)
        )

        self.imageNode = TransformImageNode()

        super.init()

        self.speakingAudioLevelView.setColor(.white)
        self.speakingAudioLevelView.alpha = 1.0

        self.imageNode.contentAnimations = [.subsequentUpdates]

        self.view.addSubview(speakingAudioLevelView)
        self.addSubnode(self.imageNode)
    }

    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) -> CGSize {

        let imageSize = CGSize(width: 136, height: 136)
        let levelSize = CGSize(width: imageSize.width*1.7, height: imageSize.height*1.7)

        let levelFrame = CGRect(origin: CGPoint(), size: levelSize)
        self.speakingAudioLevelView.frame = levelFrame

        let imageFrame = CGRect(origin: .init(x: levelSize.width/2 - imageSize.width/2, y: levelSize.height/2 - imageSize.height/2), size: imageSize)
        transition.updateFrame(node: self.imageNode, frame: imageFrame)

        let arguments = TransformImageArguments(corners: ImageCorners(radius: imageSize.width/2), imageSize: CGSize(width: 640.0, height: 640.0).aspectFilled(imageFrame.size), boundingSize: imageFrame.size, intrinsicInsets: UIEdgeInsets())
        let apply = self.imageNode.asyncLayout()(arguments)
        apply()

        return levelSize
    }
}
