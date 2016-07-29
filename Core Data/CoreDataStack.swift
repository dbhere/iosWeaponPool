//
//  CoreDataStack.swift
//
//
//  Created by HhhotDog on 16/7/22.
//  Copyright © 2016年 Alexscott. All rights reserved.
//

import CoreData

struct CoreDataStack {
    
    // MARK:  - Properties
    private let model : NSManagedObjectModel
    private let coordinator : NSPersistentStoreCoordinator
    private let modelURL : NSURL
    private let dbURL : NSURL
    private let persistingContext: NSManagedObjectContext
    private let backgroundContext: NSManagedObjectContext
    let context : NSManagedObjectContext
    
    // MARK:  - Initializers
    init?(modelName: String){
        
        // Assumes the model is in the main bundle
        guard let modelURL = NSBundle.mainBundle().URLForResource(modelName, withExtension: "momd") else {
            print("Unable to find \(modelName)in the main bundle")
            return nil}
        
        self.modelURL = modelURL
        
        // Try to create the model from the URL
        guard let model = NSManagedObjectModel(contentsOfURL: modelURL) else{
            print("unable to create a model from \(modelURL)")
            return nil
        }
        self.model = model
        
        
        
        // Create the store coordinator
        coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        
        // create a context and add connect it to the coordinator
        persistingContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        persistingContext.persistentStoreCoordinator = coordinator
        
        context = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        context.parentContext = persistingContext
        
        backgroundContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        backgroundContext.parentContext = context
        
        // Add a SQLite store located in the documents folder
        let fm = NSFileManager.defaultManager()
        
        guard let  docUrl = fm.URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask).first else{
            print("Unable to reach the documents folder")
            return nil
        }
        
        self.dbURL = docUrl.URLByAppendingPathComponent("model.sqlite")
        
        //migration options
        do{
            let options = [NSInferMappingModelAutomaticallyOption: true,
                           NSMigratePersistentStoresAutomaticallyOption: true]
            try addStoreCoordinator(NSSQLiteStoreType, configuration: nil, storeURL: dbURL, options: options)
            
        }catch{
            print("unable to add store at \(dbURL)")
        }
    }
    
    // MARK:  - Utils
    func addStoreCoordinator(storeType: String,
                             configuration: String?,
                             storeURL: NSURL,
                             options : [NSObject : AnyObject]?) throws{
        
        try coordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: configuration, URL: dbURL, options: options)
        
    }
}


// MARK:  - Removing data
extension CoreDataStack  {
    
    func dropAllData() throws{
        // delete all the objects in the db. This won't delete the files, it will
        // just leave empty tables.
        try coordinator.destroyPersistentStoreAtURL(dbURL, withType:NSSQLiteStoreType , options: nil)
        
        try addStoreCoordinator(NSSQLiteStoreType, configuration: nil, storeURL: dbURL, options: nil)
        
        
    }
}

// MARK:  - Batch processing in the background
extension CoreDataStack{
    typealias Batch = (workerContext: NSManagedObjectContext) -> Void
    func performBackgroundBatchOperation(batch: Batch){
        backgroundContext.performBlock {
            batch(workerContext: self.backgroundContext)
            do {
                try self.backgroundContext.save()
            } catch {
                fatalError("Error while saving backgroundContext: \(error)")
            }
        }
    }
}

// MARK:  - Save
extension CoreDataStack {
    
    func saveContext() {
        context.performBlockAndWait {
            do {
                try self.context.save()
            } catch {
                fatalError("Error while saving main context: \(error)")
            }
            
            self.persistingContext.performBlock({
                do {
                    try self.persistingContext.save()
                } catch {
                    fatalError("Error while saving main context: \(error)")
                }
            })
        }
    }
    
    func autoSave(delayInSeconds : Int){
        
        if delayInSeconds > 0 {
            print("Autosaving")
            saveContext()
            
            let delayInNanoSeconds = UInt64(delayInSeconds) * NSEC_PER_SEC
            let time = dispatch_time(DISPATCH_TIME_NOW, Int64(delayInNanoSeconds))
            
            dispatch_after(time, dispatch_get_main_queue(), {
                self.autoSave(delayInSeconds)
            })
        }
    }
}