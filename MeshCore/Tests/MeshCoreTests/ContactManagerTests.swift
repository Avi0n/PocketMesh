import Foundation
import Testing
@testable import MeshCore

@Suite("ContactManager Tests")
struct ContactManagerTests {

    @Test("Cache update stores contacts correctly")
    func cacheUpdate() {
        var manager = ContactManager()
        let contact = MeshContact.mock(name: "TestNode")

        manager.updateCache([contact], lastModified: Date())

        #expect(manager.cachedContacts.count == 1)
        #expect(manager.cachedContacts.first?.advertisedName == "TestNode")
        #expect(manager.needsRefresh == false)
    }

    @Test("Lookup by name uses localized search")
    func lookupByName() {
        var manager = ContactManager()
        let contact = MeshContact.mock(name: "MyDevice")
        manager.updateCache([contact], lastModified: Date())

        let found = manager.getByName("mydevice") // lowercase
        #expect(found != nil)
        #expect(found?.advertisedName == "MyDevice")
    }

    @Test("Lookup by name exact match")
    func lookupByNameExact() {
        var manager = ContactManager()
        let contact = MeshContact.mock(name: "MyDevice")
        manager.updateCache([contact], lastModified: Date())

        // Exact match (case-insensitive)
        let found = manager.getByName("mydevice", exactMatch: true)
        #expect(found != nil)

        // Partial should not match with exact
        let notFound = manager.getByName("MyDev", exactMatch: true)
        #expect(notFound == nil)
    }

    @Test("Lookup by key prefix (String)")
    func lookupByKeyPrefixString() {
        var manager = ContactManager()
        let publicKey = Data([0xAB, 0xCD, 0xEF] + [UInt8](repeating: 0x00, count: 29))
        let contact = MeshContact.mock(name: "TestNode", publicKey: publicKey)
        manager.updateCache([contact], lastModified: Date())

        let found = manager.getByKeyPrefix("abcd")
        #expect(found != nil)
        #expect(found?.advertisedName == "TestNode")

        let notFound = manager.getByKeyPrefix("1234")
        #expect(notFound == nil)
    }

    @Test("Lookup by key prefix (Data)")
    func lookupByKeyPrefixData() {
        var manager = ContactManager()
        let publicKey = Data([0xAB, 0xCD, 0xEF] + [UInt8](repeating: 0x00, count: 29))
        let contact = MeshContact.mock(name: "TestNode", publicKey: publicKey)
        manager.updateCache([contact], lastModified: Date())

        let found = manager.getByKeyPrefix(Data([0xAB, 0xCD]))
        #expect(found != nil)
        #expect(found?.advertisedName == "TestNode")

        let notFound = manager.getByKeyPrefix(Data([0x12, 0x34]))
        #expect(notFound == nil)
    }

    @Test("Pending contacts lifecycle")
    func pendingContactsLifecycle() {
        var manager = ContactManager()
        let contact = MeshContact.mock(name: "Pending")

        manager.addPending(contact)
        #expect(manager.cachedPendingContacts.count == 1)

        let popped = manager.popPending(publicKey: contact.id)
        #expect(popped?.advertisedName == "Pending")
        #expect(manager.cachedPendingContacts.isEmpty)
    }

    @Test("Flush pending contacts")
    func flushPending() {
        var manager = ContactManager()
        manager.addPending(MeshContact.mock(name: "Pending1"))
        manager.addPending(MeshContact.mock(name: "Pending2", publicKey: Data(repeating: 0xCD, count: 32)))
        #expect(manager.cachedPendingContacts.count == 2)

        manager.flushPending()
        #expect(manager.cachedPendingContacts.isEmpty)
    }

    @Test("Mark dirty triggers refresh need")
    func markDirty() {
        var manager = ContactManager()
        manager.updateCache([], lastModified: Date())
        #expect(manager.needsRefresh == false)

        manager.markDirty()
        #expect(manager.needsRefresh == true)
    }

    @Test("Store single contact")
    func storeSingleContact() {
        var manager = ContactManager()
        let contact = MeshContact.mock(name: "StoredNode")

        manager.store(contact)

        #expect(manager.cachedContacts.count == 1)
        #expect(manager.getByName("StoredNode") != nil)
    }

    @Test("Mark clean sets lastModified and clears dirty")
    func markClean() {
        var manager = ContactManager()
        #expect(manager.needsRefresh == true)
        #expect(manager.contactsLastModified == nil)

        let date = Date()
        manager.markClean(lastModified: date)

        #expect(manager.needsRefresh == false)
        #expect(manager.contactsLastModified == date)
    }

    @Test("isEmpty reflects contact count")
    func isEmptyProperty() {
        var manager = ContactManager()
        #expect(manager.isEmpty == true)

        manager.store(MeshContact.mock())
        #expect(manager.isEmpty == false)
    }

    @Test("Remove contact")
    func removeContact() {
        var manager = ContactManager()
        let contact = MeshContact.mock(name: "ToRemove")
        manager.store(contact)
        #expect(manager.cachedContacts.count == 1)

        manager.remove(contact.id)
        #expect(manager.cachedContacts.isEmpty)
        #expect(manager.needsRefresh == true)
    }

    @Test("Clear removes all data")
    func clear() {
        var manager = ContactManager()
        manager.store(MeshContact.mock(name: "Contact1"))
        manager.addPending(MeshContact.mock(name: "Pending1", publicKey: Data(repeating: 0xCD, count: 32)))
        manager.markClean(lastModified: Date())

        manager.clear()

        #expect(manager.cachedContacts.isEmpty)
        #expect(manager.cachedPendingContacts.isEmpty)
        #expect(manager.contactsLastModified == nil)
        #expect(manager.needsRefresh == true)
    }

    @Test("Auto update flag")
    func autoUpdateFlag() {
        var manager = ContactManager()
        #expect(manager.isAutoUpdateEnabled == false)

        manager.setAutoUpdate(true)
        #expect(manager.isAutoUpdateEnabled == true)

        manager.setAutoUpdate(false)
        #expect(manager.isAutoUpdateEnabled == false)
    }

    @Test("Track changes updates state from contact event")
    func trackChangesContact() {
        var manager = ContactManager()
        let contact = MeshContact.mock(name: "EventContact")

        manager.trackChanges(from: .contact(contact))
        #expect(manager.cachedContacts.count == 1)
        #expect(manager.getByName("EventContact") != nil)
    }

    @Test("Track changes adds new contact to pending")
    func trackChangesNewContact() {
        var manager = ContactManager()
        let contact = MeshContact.mock(name: "NewContact")

        manager.trackChanges(from: .newContact(contact))

        #expect(manager.cachedPendingContacts.count == 1)
        #expect(manager.needsRefresh == true)
    }

    @Test("Track changes handles contactsEnd")
    func trackChangesContactsEnd() {
        var manager = ContactManager()
        manager.markDirty()
        #expect(manager.needsRefresh == true)

        let lastModified = Date()
        manager.trackChanges(from: .contactsEnd(lastModified: lastModified))

        #expect(manager.needsRefresh == false)
        #expect(manager.contactsLastModified == lastModified)
    }

    @Test("Track changes marks dirty on advertisement")
    func trackChangesAdvertisement() {
        var manager = ContactManager()
        manager.markClean(lastModified: Date())
        #expect(manager.needsRefresh == false)

        manager.trackChanges(from: .advertisement(publicKey: Data(repeating: 0xAB, count: 32)))

        #expect(manager.needsRefresh == true)
    }

    @Test("Track changes marks dirty on pathUpdate")
    func trackChangesPathUpdate() {
        var manager = ContactManager()
        manager.markClean(lastModified: Date())
        #expect(manager.needsRefresh == false)

        manager.trackChanges(from: .pathUpdate(publicKey: Data([0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56])))

        #expect(manager.needsRefresh == true)
    }
}
