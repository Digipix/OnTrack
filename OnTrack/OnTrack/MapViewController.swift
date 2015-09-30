//
//  MapViewController.swift
//  OnTrack
//
//  Created by Daren David Taylor on 01/09/2015.
//  Copyright (c) 2015 LondonSwift. All rights reserved.
//

import UIKit
import MapKit
import AudioToolbox
import LSRepeater

public enum MapType: String {
    case AppleStandard = "Std"
    case AppleSatellite = "Sat"
    case AppleHybrid = "Mix"
}

public enum ZoomType: String {
    case You = "You"
    case All = "All"
}

class MapViewController: UIViewController {
    
    var repeater: LSRepeater?
    
    var currentLocation: CLLocation?
    
    var currentLocationToNearestPolyline:MKPolyline?
    var currentLocationToNearestRenderer:MKPolylineRenderer?
    
    // For displaying the lines of the route
    var polylineArray:Array<MKPolyline>?
    var rendererArray:Array<MKPolylineRenderer>?
    
    // the actual array of arrays of points, for off track detection
    var interpolatedLocationArray:Array<CLLocation>?
    
    @IBOutlet weak var mapTypeButton: UIButton!
    @IBOutlet weak var zoomTypeButton: UIButton!
    
    @IBOutlet weak var mapView: MKMapView!
    
    var mapType:MapType = .AppleStandard
    var zoomType:ZoomType = .All
    var boundingRect:MKMapRect?
    var overlay:MKTileOverlay?
    
    var locationManager: CLLocationManager!
    
    var found = false
    
    @IBOutlet weak var distanceButton: UIButton!
    var locationArrayArray:Array<Array<CLLocation>>?
    
    func loadRoute(filename:String) {
        let url = NSURL.applicationDocumentsDirectory().URLByAppendingPathComponent(filename)
        
        self.locationArrayArray = Array<Array<CLLocation>>()
        
        if let root = GPXParser.parseGPXAtURL(url) {
            
            if let tracks = root.tracks {
                for track in tracks as! [GPXTrack] {
                    
                    for trackSegment in track.tracksegments as! [GPXTrackSegment] {
                        var array = [CLLocation]()
                        for trackPoint in  trackSegment.trackpoints as! [GPXTrackPoint] {
                            let location = CLLocation(latitude: CLLocationDegrees(trackPoint.latitude), longitude: CLLocationDegrees(trackPoint.longitude))
                            array.append(location)
                        }
                        self.locationArrayArray!.append(array)
                    }
                }
            }
            
            if let routes = root.routes {
                for route in routes as! [GPXRoute] {
                    var array = [CLLocation]()
                    
                    for routePoint in  route.routepoints as! [GPXRoutePoint] {
                        let location = CLLocation(latitude: CLLocationDegrees(routePoint.latitude), longitude: CLLocationDegrees(routePoint.longitude))
                        array.append(location)
                    }
                    
                    self.locationArrayArray!.append(array)
                }
            }
        }
        
        self.interpolateWith(5)
        self.popolateMapWithPolyline()
        self.zoomMapToRoute()
    }
    
    @IBAction func didPressMapTypeButton(sender: AnyObject) {
        
        self.mapType = [MapType.AppleSatellite ,MapType.AppleHybrid, MapType.AppleStandard][[MapType.AppleStandard, MapType.AppleSatellite, MapType.AppleHybrid].indexOf(self.mapType)!]
        
        self.updateMapTypeButton()
        self.updateMapType()
    }
    
    @IBAction func didPressZoomTypeButton(sender: AnyObject) {
        
        if self.zoomType == .All { self.zoomType = .You }
        else { self.zoomType = .All }
        
        self.updateZoomTypeButton()
        
        self.updateZoomType()
        
    }
    
    func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        
        let vc = segue.destinationViewController as! FileListTableViewController
        
        vc.delegate = self
    }
    
    func updateMapTypeButton() {
        self.mapTypeButton.setTitle(self.mapType.rawValue, forState: .Normal)
    }
    func updateZoomTypeButton() {
        self.zoomTypeButton.setTitle(self.zoomType.rawValue, forState: .Normal)
    }
    

    
    func updateZoomType() {
        switch self.zoomType {
        case .All:
            self.calculateBoundingRect()
            self.zoomMapToRoute()
        case .You:
            self.mapView.setUserTrackingMode(.FollowWithHeading, animated:true);
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.mapView.delegate = self
        self.mapView.showsUserLocation = true
        self.updateMapType()
        self.updateZoomType()
        self.updateZoomTypeButton()
        self.updateMapTypeButton()
        self.setupLocationManager()
        
        let defaults = NSUserDefaults.standardUserDefaults()
        
        if let file = defaults.objectForKey("file") as? String {
            self.loadRoute(file)
        }
        
    }
    
    func setupLocationManager() {
        self.locationManager = CLLocationManager()
        self.locationManager.delegate = self
        
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        self.locationManager.delegate = self;
        
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.startUpdatingLocation()
    }
    
    func calculateBoundingRect () {
        self.boundingRect = MKMapRectNull;
        
        if let location = self.mapView.userLocation.location {
            
            let point = MKMapPointForCoordinate(location.coordinate)
            self.boundingRect = MKMapRectMake(point.x, point.y,0,0);
        }
        
        
        if let polylineArray = self.polylineArray {
            
            for polyline in polylineArray {
                
                if let boundingRect = self.boundingRect {
                    self.boundingRect = MKMapRectUnion(polyline.boundingMapRect, boundingRect);
                }
                else {
                    self.boundingRect = polyline.boundingMapRect;
                }
                
            }
        }
        
        if let boundingRect = self.boundingRect {
            self.boundingRect = MKMapRectInset(boundingRect, -boundingRect.size.width / 2, -boundingRect.size.height/2);
        }
    }
    
    func popolateMapWithPolyline()
    {
        self.polylineArray = Array<MKPolyline>()
        self.rendererArray = Array<MKPolylineRenderer>()
        
        for locationArray in self.locationArrayArray! {
            let coordinates = UnsafeMutablePointer<CLLocationCoordinate2D>.alloc(locationArray.count)
            var i = 0
            for location in locationArray {
                coordinates[i++] = location.coordinate;
            }
            
            let polyline = MKPolyline(coordinates: coordinates, count: locationArray.count)
            let renderer = MKPolylineRenderer(polyline: polyline)
            
            renderer.strokeColor = UIColor.darkGrayColor()
            renderer.lineWidth = 3;
            
            self.polylineArray?.append(polyline)
            self.rendererArray?.append(renderer)
            
            self.mapView.addOverlay(polyline, level:.AboveLabels);
        }
        
        self.calculateBoundingRect()
    }
    
    func zoomMapToRoute() {
        
        if let boundingRect = self.boundingRect {
            self.mapView.setVisibleMapRect(boundingRect, animated:true);
        }
    }
    
    func updateMapType() {
        
        if let overlay = self.overlay {
            
            self.mapView.removeOverlay(overlay);
            
            self.overlay = nil;
        }
        switch (self.mapType)
        {
        case .AppleStandard:
            self.mapView.mapType = .Standard;
        case .AppleSatellite:
            self.mapView.mapType = .Satellite;
        case .AppleHybrid:
            self.mapView.mapType = .Hybrid;
        }
    }
}

extension MapViewController : MKMapViewDelegate {
    func mapView(mapView: MKMapView, didChangeUserTrackingMode mode: MKUserTrackingMode, animated: Bool) {
        switch mode {
        case .None, .Follow:
            self.zoomType = .All
        case .FollowWithHeading:
            self.zoomType = .You
        }
    }
    
    func mapView(mapView: MKMapView, rendererForOverlay overlay: MKOverlay) -> MKOverlayRenderer {
        
        if overlay.isKindOfClass(MKTileOverlay) {
            return MKTileOverlayRenderer(overlay: overlay)
        }
        
        if let polylineArray = self.polylineArray {
            
            if let overlay = overlay as? MKPolyline {
                if let i = polylineArray.indexOf(overlay) {
                    
                    if let rendererArray = self.rendererArray {
                        
                        return rendererArray[i]
                    }
                }
                else {
                    print("not found")
                }
                
            }
        }
        return MKTileOverlayRenderer(overlay: overlay)
    }
    
    func interpolateWith(metres: CLLocationDistance) {
        self.interpolatedLocationArray = [CLLocation]()
        var lastLocation: CLLocation?
        
        for locationArray in self.locationArrayArray! {
            for location in locationArray {
                if let lastLocation = lastLocation {
                    let distance = location.distanceFromLocation(lastLocation)
                    let bearing = self.bearingToLocation(location, fromLocation:lastLocation);
                    for var i:CLLocationDistance = 0 ; i < distance / metres ; i++ {
                        
                        let cooridinate = self.locationWithBearing(bearing, distance:metres*i, origin:lastLocation.coordinate)
                        
                        let interpolatedLocation = CLLocation(latitude: cooridinate.latitude, longitude:cooridinate.longitude)
                        
                        self.interpolatedLocationArray?.append(interpolatedLocation)
                    }
                }
                lastLocation = location
            }
        }
    }
    
    func locationWithBearing(bearing:CLLocationDistance, distance:CLLocationDistance, origin:CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let distRadians = distance / (6372797.6) // earth radius in meters
        
        let lat1 = origin.latitude * M_PI / 180
        let lon1 = origin.longitude * M_PI / 180
        
        let lat2 = asin( sin(lat1) * cos(distRadians) + cos(lat1) * sin(distRadians) * cos(bearing))
        let lon2 = lon1 + atan2( sin(bearing) * sin(distRadians) * cos(lat1), cos(distRadians) - sin(lat1) * sin(lat2) )
        
        return CLLocationCoordinate2D(latitude: lat2 * 180 / M_PI, longitude: lon2 * 180 / M_PI)
    }
    
    func degreesToRadians(degrees: CLLocationDegrees) -> Double {
        return degrees * M_PI / 180
    }
    
    func bearingToLocation(location: CLLocation, fromLocation:CLLocation) ->Double {
        
        let lat1 = self.degreesToRadians(fromLocation.coordinate.latitude)
        let lon1 = self.degreesToRadians(fromLocation.coordinate.longitude);
        
        let lat2 = self.degreesToRadians(location.coordinate.latitude);
        let lon2 = self.degreesToRadians(location.coordinate.longitude);
        
        
        let dLon = lon2 - lon1;
        
        let y = sin(dLon) * cos(lat2);
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
        let radiansBearing = atan2(y, x);
        
        return radiansBearing;
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true;
    }
}

extension MapViewController : CLLocationManagerDelegate {
    
    func locationManager(manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        
        self.currentLocation = locations.first
        
        if self.repeater == nil {
            self.repeater = LSRepeater.repeater(5, execute: { () -> Void in
                
                var minimumDistance: CLLocationDistance = CLLocationDistance.infinity;
                
                var closestLocation: CLLocation?
                
                if let interpolatedLocationArray = self.interpolatedLocationArray {
                    
                    for location in interpolatedLocationArray {
                        let distance = location.distanceFromLocation(self.currentLocation!);
                        minimumDistance = min(minimumDistance, distance);
                        
                        if minimumDistance == distance {
                            closestLocation = location
                        }
                        
                    }
                    
                    let warningDistance:CLLocationDistance = 100
                    
                    if minimumDistance > warningDistance {
                        AudioServicesPlaySystemSound (1033);
                        self.found = false;
                    }
                    else {
                        if self.found == false {
                            AudioServicesPlaySystemSound (1028);
                        }
                        self.found = true;
                    }
                    
                    self.distanceButton.setTitle(String(format:"%.2fm", minimumDistance), forState: .Normal)
                    
                }
                
                // remove closest line
                
                if let currentLocationToNearestPolyline = self.currentLocationToNearestPolyline {
                    if let index = self.polylineArray?.indexOf(currentLocationToNearestPolyline) {
                        self.polylineArray?.removeAtIndex(index)
                    }
                }
                
                if let currentLocationToNearestRenderer = self.currentLocationToNearestRenderer {
                    if let index = self.rendererArray?.indexOf(currentLocationToNearestRenderer) {
                        self.rendererArray?.removeAtIndex(index)
                    }
                }
                // end remove closest line
                
                // add closest line
                if let currentLocation = self.currentLocation, closestLocation = closestLocation {
                    
                    let coordinates = UnsafeMutablePointer<CLLocationCoordinate2D>.alloc(2)
                    coordinates[0] = currentLocation.coordinate;
                    coordinates[1] = closestLocation.coordinate;
                    
                    self.currentLocationToNearestPolyline = MKPolyline(coordinates: coordinates, count: 2)
                    self.currentLocationToNearestRenderer = MKPolylineRenderer(polyline: self.currentLocationToNearestPolyline!)
                    
                    self.currentLocationToNearestRenderer!.strokeColor = UIColor.redColor()
                    self.currentLocationToNearestRenderer!.lineWidth = 1;
                    //      self.currentLocationToNearestPolyline!.lineDashPattern = 5
                    
                    self.polylineArray?.append(self.currentLocationToNearestPolyline!)
                    self.rendererArray?.append(self.currentLocationToNearestRenderer!)
                    
                    self.mapView.addOverlay(self.currentLocationToNearestPolyline!, level:.AboveLabels);
                }
                // end add closest line
                
            })
        }
        
        
        
    }
}

extension MapViewController : FileListTableViewControllerDelegate {
    
    func fileListTableViewController(fileListTableViewController: FileListTableViewController, didSelectFile: String){
  
        self.loadRoute(didSelectFile)
        
        }
    }
    
    func fileListTableViewControllerDidCancel(fileListTableViewController: FileListTableViewController){
        self.dismissViewControllerAnimated(true) { () -> Void in
            
    }
    
}



