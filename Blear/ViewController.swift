import UIKit
import Photos
import FDTake
import IIDelayedAction
import JGProgressHUD

let IS_IPAD = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.pad
let IS_IPHONE = UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiom.phone
let SCREEN_WIDTH = UIScreen.main.bounds.size.width
let SCREEN_HEIGHT = UIScreen.main.bounds.size.height
let IS_LARGE_SCREEN = IS_IPHONE && max(SCREEN_WIDTH, SCREEN_HEIGHT) >= 736.0

struct Constants {
	static let scrollMinimumScale: CGFloat = 1.0
	static let scrollMaximumScale: CGFloat = 10.0
	static let minimumBlurValue: Float = 0
	static let maximumBlurValue: Float = 100
	static let originalImage = "Original Image"
	static let reuseIdentifier = "FilterImagePreviewCell"
	static var CIFilterNames = [
		"CIPhotoEffectChrome",
		"CIPhotoEffectFade",
		"CIPhotoEffectInstant",
		"CIPhotoEffectNoir",
		"CIPhotoEffectProcess",
		"CIPhotoEffectTonal",
		"CIPhotoEffectTransfer",
		"CISepiaTone"
	]
	static let collectionItemWidth: CGFloat = 100
	static let collectionItemHeight: CGFloat = 120
	static let animationDuration = 0.3
}

final class ViewController: UIViewController {
	var sourceImage: UIImage?
	var delayedAction: IIDelayedAction?
	var blurAmount: Float = Constants.minimumBlurValue
	let stockImages = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: "Bundled Photos")!
	lazy var randomImageIterator: AnyIterator<URL> = self.stockImages.uniqueRandomElement()
	var currentFilterEffectIndex = 0
	var filterApplied = false
	var originalImage: UIImage?

	lazy var imageView = with(UIImageView()) {
		$0.image = UIImage(color: .black, size: view.frame.size)
		$0.contentMode = .scaleAspectFill
		$0.clipsToBounds = true
		$0.frame = view.bounds
		$0.isUserInteractionEnabled = true
	}

	lazy var effectTitleLabel = with(UILabel()) {
		$0.frame = CGRect(x: 0, y: 0, width: view.frame.size.width, height: 40)
		$0.textAlignment = .center
		$0.font = UIFont.boldSystemFont(ofSize: 16.0)
		$0.textColor = UIColor(red: 225, green: 74, blue: 119, alpha: 1.0)
		$0.text = Constants.originalImage
	}

	// To perform pinch operation similar to Insta
	lazy var bottomScrollView = with(UIScrollView()) {
		$0.frame = view.frame
		$0.alwaysBounceVertical = false
		$0.alwaysBounceHorizontal = false
		$0.minimumZoomScale = Constants.scrollMinimumScale
		$0.maximumZoomScale = Constants.scrollMaximumScale
		$0.delegate = self
	}

	lazy var layout = with(UICollectionViewFlowLayout()) {
		$0.scrollDirection = .vertical
		$0.sectionInset = UIEdgeInsets(top: 15, left: 5, bottom: 15, right: 5)
		$0.itemSize = CGSize(width: Constants.collectionItemWidth, height: Constants.collectionItemHeight)
	}

	lazy var filterImagePreviewCollectionView = with(UICollectionView(frame: CGRect(x: -150, y: 60, width: Constants.collectionItemWidth, height: self.view.bounds.height - 150), collectionViewLayout: layout)) {
		$0.register(FilterImagePreviewCell.self, forCellWithReuseIdentifier: Constants.reuseIdentifier)
		$0.dataSource = self
		$0.delegate = self
		$0.showsHorizontalScrollIndicator = false
		$0.showsVerticalScrollIndicator = true
		$0.backgroundColor = .clear
		$0.isHidden = true
	}

	lazy var slider = with(UISlider()) {
		let SLIDER_MARGIN: CGFloat = 120
		$0.frame = CGRect(x: 0, y: 0, width: view.frame.size.width - SLIDER_MARGIN, height: view.frame.size.height)
		$0.minimumValue = Constants.minimumBlurValue
		$0.maximumValue = Constants.maximumBlurValue
		$0.value = blurAmount
		$0.isContinuous = true
		$0.setThumbImage(UIImage(named: "SliderThumb")!, for: .normal)
		$0.autoresizingMask = [
			.flexibleWidth,
			.flexibleTopMargin,
			.flexibleBottomMargin,
			.flexibleLeftMargin,
			.flexibleRightMargin
		]
		$0.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
	}

	override var canBecomeFirstResponder: Bool {
		return true
	}

	override var prefersStatusBarHidden: Bool {
		return true
	}

	override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
		if motion == .motionShake {
			randomImage()
		}
	}

	override func viewDidLoad() {
		super.viewDidLoad()

		// This is to ensure that it always ends up with the current blur amount when the slider stops
		// since we're using `DispatchQueue.global().async` the order of events aren't serial
		delayedAction = IIDelayedAction({}, withDelay: 0.2)
		delayedAction?.onMainThread = false

		// Adding scroll view and imageview to view
		view.addSubview(bottomScrollView)
		bottomScrollView.addSubview(imageView)
		view.addSubview(effectTitleLabel)

		let TOOLBAR_HEIGHT: CGFloat = 80 + window.safeAreaInsets.bottom
		let toolbar = UIToolbar(frame: CGRect(x: 0, y: view.frame.size.height - TOOLBAR_HEIGHT, width: view.frame.size.width, height: TOOLBAR_HEIGHT))
		toolbar.autoresizingMask = .flexibleWidth
		toolbar.alpha = 0.6
		toolbar.tintColor = #colorLiteral(red: 0.98, green: 0.98, blue: 0.98, alpha: 1)

		// Remove background
		toolbar.setBackgroundImage(UIImage(), forToolbarPosition: .any, barMetrics: .default)
		toolbar.setShadowImage(UIImage(), forToolbarPosition: .any)

		// Gradient background
		let GRADIENT_PADDING: CGFloat = 40
		let gradient = CAGradientLayer()
		gradient.frame = CGRect(x: 0, y: -GRADIENT_PADDING, width: toolbar.frame.size.width, height: toolbar.frame.size.height + GRADIENT_PADDING)
		gradient.colors = [
			UIColor.clear.cgColor,
			UIColor.black.withAlphaComponent(0.1).cgColor,
			UIColor.black.withAlphaComponent(0.3).cgColor,
			UIColor.black.withAlphaComponent(0.4).cgColor
		]
		toolbar.layer.addSublayer(gradient)

		toolbar.items = [
			UIBarButtonItem(image: UIImage(named: "PickButton")!, target: self, action: #selector(pickImage), width: 20),
			.flexibleSpace,
			UIBarButtonItem(customView: slider),
			.flexibleSpace,
			UIBarButtonItem(image: UIImage(named: "SaveButton")!, target: self, action: #selector(saveImage), width: 20)
		]
		view.addSubview(toolbar)

		// Important that this is here at the end for the fading to work
		randomImage()
		addRequiredGestures()
	}

	func addRequiredGestures() {
		addLongPressGestureToImageView()
		addRightSwipeGestureRecognizer()
		addLeftSwipeGestureRecognizer()
	}

	func addFiltertoImageView(filterIndex: Int) {
		let ciContext = CIContext(options: nil)
		if let originalImage = originalImage {
			let coreImage = CIImage(image: originalImage)
			let filter = CIFilter(name: "\(Constants.CIFilterNames[filterIndex])" )
			effectTitleLabel.text = Constants.CIFilterNames[filterIndex]
			filter!.setDefaults()
			filter!.setValue(coreImage, forKey: kCIInputImageKey)
			let filteredImageData = filter!.value(forKey: kCIOutputImageKey) as! CIImage
			let filteredImageRef = ciContext.createCGImage(filteredImageData, from: filteredImageData.extent)
			let filteredImage = UIImage(cgImage: filteredImageRef!)
			imageView.image = filteredImage
			sourceImage = filteredImage
		}
		slider.value = Constants.minimumBlurValue
	}

	func getFilteredImage(filterIndex: Int) -> UIImage {
		let ciContext = CIContext(options: nil)
		let coreImage = CIImage(image: originalImage!)
		let filter = CIFilter(name: "\(Constants.CIFilterNames[filterIndex])" )
		filter!.setDefaults()
		filter!.setValue(coreImage, forKey: kCIInputImageKey)
		let filteredImageData = filter!.value(forKey: kCIOutputImageKey) as! CIImage
		let filteredImageRef = ciContext.createCGImage(filteredImageData, from: filteredImageData.extent)
		let filteredImage = UIImage(cgImage: filteredImageRef!)
		return filteredImage
	}

	@objc
	func pickImage() {
		let fdTake = FDTakeController()
		fdTake.allowsVideo = false
		fdTake.didGetPhoto = { photo, _ in
			self.changeImage(photo)
		}
		fdTake.present()
	}

	func blurImage(_ blurAmount: Float) -> UIImage {
		return UIImageEffects.imageByApplyingBlur(
			to: sourceImage,
			withRadius: CGFloat(blurAmount * (IS_LARGE_SCREEN ? 0.8 : 1.2)),
			tintColor: UIColor(white: 1, alpha: CGFloat(max(0, min(0.25, blurAmount * 0.004)))),
			saturationDeltaFactor: CGFloat(max(1, min(2.8, blurAmount * (IS_IPAD ? 0.035 : 0.045)))),
			maskImage: nil
		)
	}

	@objc
	func updateImage() {
		DispatchQueue.global(qos: .userInteractive).async {
			let tmp = self.blurImage(self.blurAmount)
			DispatchQueue.main.async {
				self.imageView.image = tmp
			}
		}
	}

	func updateImageDebounced() {
		performSelector(inBackground: #selector(updateImage), with: IS_IPAD ? 0.1 : 0.06)
	}

	func addLongPressGestureToImageView() {
		let longTapGesture = UILongPressGestureRecognizer(target: self, action: #selector(longPressActionPerformed))
		imageView.addGestureRecognizer(longTapGesture)
	}

	func addRightSwipeGestureRecognizer() {
		let rightSwipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(swipActionRecognized))
		rightSwipeGesture.direction = .right
		bottomScrollView.addGestureRecognizer(rightSwipeGesture)
	}

	func addLeftSwipeGestureRecognizer() {
		let leftSwipeGesture = UISwipeGestureRecognizer(target: self, action: #selector(swipActionRecognized))
		leftSwipeGesture.direction = .left
		bottomScrollView.addGestureRecognizer(leftSwipeGesture)
	}

	@objc
	func swipActionRecognized(gesture: UISwipeGestureRecognizer) {
		if gesture.direction == .left {
			if filterApplied == false {
				filterApplied = true
			} else {
				currentFilterEffectIndex += 1
				if currentFilterEffectIndex >= Constants.CIFilterNames.count {
					resetSwipe()
					return
				}
			}
			addFiltertoImageView(filterIndex: currentFilterEffectIndex)
		} else if gesture.direction == .right {
			if filterApplied == false {
				return
			}
			currentFilterEffectIndex -= 1
			if currentFilterEffectIndex == -1 {
				resetSwipe()
				return
			}
			addFiltertoImageView(filterIndex: currentFilterEffectIndex)
		}
	}

	func resetSwipe() {
		filterApplied = false
		currentFilterEffectIndex = 0
		imageView.image = originalImage
		sourceImage = originalImage
		effectTitleLabel.text = Constants.originalImage
	}

	@objc
	func longPressActionPerformed(sender: UILongPressGestureRecognizer) {
		if sender.state == .began {
			if let imageToShare = imageView.image {
				performImageShareAction(shareImage: imageToShare)
			}
		}
	}

	func performImageShareAction(shareImage: UIImage) {
		let itemsToShare = [shareImage]
		let activityController = UIActivityViewController(activityItems: itemsToShare, applicationActivities: nil)
		activityController.modalTransitionStyle = .coverVertical
		self.present(activityController, animated: true) {
			//TODO: Implemet any share completion action here.
		}
	}

	@objc
	func sliderChanged(_ sender: UISlider) {
		blurAmount = sender.value
		updateImageDebounced()
		delayedAction?.action {
			self.updateImage()
		}
	}

	@objc
	func saveImage(_ button: UIBarButtonItem) {
		button.isEnabled = false

		PHPhotoLibrary.save(image: imageView.image!, toAlbum: "Blear") { result in
			button.isEnabled = true

			let HUD = JGProgressHUD(style: .dark)
			HUD.indicatorView = JGProgressHUDSuccessIndicatorView()
			HUD.animation = JGProgressHUDFadeZoomAnimation()
			HUD.vibrancyEnabled = true
			HUD.contentInsets = UIEdgeInsets(all: 30)

			if case .failure(let error) = result {
				HUD.indicatorView = JGProgressHUDErrorIndicatorView()
				HUD.textLabel.text = error.localizedDescription
				HUD.show(in: self.view)
				HUD.dismiss(afterDelay: 3)
				return
			}

			//HUD.indicatorView = JGProgressHUDImageIndicatorView(image: #imageLiteral(resourceName: "HudSaved"))
			HUD.show(in: self.view)
			HUD.dismiss(afterDelay: 0.8)

			// Only on first save
			if UserDefaults.standard.isFirstLaunch {
				delay(seconds: 1) {
					let alert = UIAlertController(
						title: "Changing Wallpaper",
						message: "In the Photos app go to the wallpaper you just saved, tap the action button on the bottom left and choose 'Use as Wallpaper'.",
						preferredStyle: .alert
					)
					alert.addAction(UIAlertAction(title: "OK", style: .default))
					self.present(alert, animated: true)
				}
			}
		}
	}

	/// TODO: Improve this method
	func changeImage(_ image: UIImage) {
		let tmp = NSKeyedUnarchiver.unarchiveObject(with: NSKeyedArchiver.archivedData(withRootObject: imageView)) as! UIImageView
		view.insertSubview(tmp, aboveSubview: imageView)
		imageView.image = image
		originalImage = image
		sourceImage = imageView.toImage()
		updateImageDebounced()
		// The delay here is important so it has time to blur the image before we start fading
		UIView.animate(
			withDuration: 0.6,
			delay: 0.3,
			options: .curveEaseInOut,
			animations: {
				tmp.alpha = 0
		}, completion: { _ in
			tmp.removeFromSuperview()
		})
	}

	func randomImage() {
		changeImage(UIImage(contentsOf: randomImageIterator.next()!)!)
		filterImagePreviewCollectionView.reloadData()
		blurAmount = Constants.minimumBlurValue
		slider.value = Constants.minimumBlurValue
		effectTitleLabel.text = Constants.originalImage
	}

	func displayPreviewCollectionView() {
		isPreviewCollectionViewHidden = false
		UIView.animate(withDuration: Constants.animationDuration) { [weak self] in
			self?.filterImagePreviewCollectionView.frame = CGRect(x: 10, y: 60, width: Constants.collectionItemWidth, height: self?.filterImagePreviewCollectionView.frame.size.height ?? 0)
			self?.filterImagePreviewCollectionView.isHidden = false
		}
	}

	func dismissPreviewCollectionView() {
		isPreviewCollectionViewHidden = true
		UIView.animate(withDuration: Constants.animationDuration) { [weak self] in
			self?.filterImagePreviewCollectionView.frame = CGRect(x: -150, y: 60, width: Constants.collectionItemWidth, height: self?.filterImagePreviewCollectionView.frame.size.height ?? 0)
				self?.filterImagePreviewCollectionView.isHidden = true
		}
	}
}

extension ViewController: UIScrollViewDelegate {
	func viewForZooming(in scrollView: UIScrollView) -> UIView? {
		return imageView
	}

	func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
		UIView.animate(withDuration: 0.3, animations: { [weak self] in
			scrollView.zoomScale = Constants.scrollMinimumScale
			self?.effectTitleLabel.isHidden = false
		})
	}

	func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
		effectTitleLabel.isHidden = true
	}
}

extension ViewController: UICollectionViewDelegate {
	func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
		if let previewCell = collectionView.cellForItem(at: indexPath) as? FilterImagePreviewCell {
			imageView.image = previewCell.imageView.image
			sourceImage = previewCell.imageView.image
			effectTitleLabel.text = Constants.CIFilterNames[indexPath.item]
			isPreviewCollectionViewHidden = true
			toolbar?.isHidden = false
			currentFilterEffectIndex = indexPath.item
			slider.value = Constants.minimumBlurValue
			dismissPreviewCollectionView()
		}
	}
}

extension ViewController: UICollectionViewDataSource {
	func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
		return Constants.CIFilterNames.count - 1
	}

	func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
		let cell = collectionView.dequeueReusableCell(withReuseIdentifier: Constants.reuseIdentifier, for: indexPath) as! FilterImagePreviewCell
		cell.imageView.image = getFilteredImage(filterIndex: indexPath.item)
		return cell
	}
}
