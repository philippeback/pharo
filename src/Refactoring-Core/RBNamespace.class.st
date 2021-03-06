"
I am a namespace for refactoring operations.
I collect changes during refactoring and provide an environment for resolving named entities like
classes, method senders or implementors. 

The default environment for a namespace contains all classes in the system, but you can create 
an instance of me with a scoped environment to apply the refactoring operations only on entities in 
that environment.

Resolving named entities includes classes and methods changed or added during refactoring, before
actually applying this changes to the system. For this, I create model classes - RBClass and RBMetaclass - modeling real classes.

The changes that will be applied to the system are collected as refactoring changes (RBRefactoryChange).

Example: 
This creates a new namespace on the default environment (all system classes):
 model := RBNamespace onEnvironment: RBBrowserEnvironment new.

This creates a Refactoring operation for adding a class, with me as the namespace model:
    refactoring := RBAddClassRefactoring
        model: model
        addClass: #SomeClass
        superclass: #Object
        subclasses: {}
        category: #Category.

This will do a ""dry run"", only collect the changes of this refactoring:
    refactoring primitiveExecute.

Now can ask me for this list of changes:
   model changes.
this acutally gives a composite refactory change that holds a list of all single refacoring changes.

Note, some of my methods for querying method senders and implementors don't work well for Trait methods, because we don't have yet modeling classes for Traits and some refactoring operations don't support refactorings on trait methods.

"
Class {
	#name : #RBNamespace,
	#superclass : #Object,
	#instVars : [
		'changes',
		'environment',
		'newClasses',
		'removedClasses',
		'changedClasses',
		'rootClasses',
		'implementorsCache',
		'sendersCache'
	],
	#category : #'Refactoring-Core-Model'
}

{ #category : #'instance creation' }
RBNamespace class >> onEnvironment: aBrowserEnvironment [ 
	^(self new)
		environment: aBrowserEnvironment;
		yourself
]

{ #category : #'private-changes' }
RBNamespace >> addChangeToClass: aRBClass [ 
	^ changedClasses 
		at: aRBClass name
		put: (Array 
				with: aRBClass instanceSide
				with: aRBClass classSide)
]

{ #category : #'private-changes' }
RBNamespace >> addClassVariable: aString to: aRBClass [ 
	^changes addClassVariable: aString to: aRBClass
]

{ #category : #'private-changes' }
RBNamespace >> addInstanceVariable: aString to: aRBClass [ 
	^changes addInstanceVariable: aString to: aRBClass
]

{ #category : #'private-changes' }
RBNamespace >> addPool: aString to: aRBClass [ 
	^changes addPool: aString to: aRBClass
]

{ #category : #accessing }
RBNamespace >> allBehaviorsDo: aBlock [
	| seen evalBlock |
	seen := Set new.
	evalBlock := [ :each | 
		seen add: each first name.
		aBlock
			value: each first;
			value: each last ].
	newClasses do: evalBlock.
	changedClasses do: evalBlock.
	environment classesDo: [ :each | 
		each isObsolete ifFalse: [
			| class |
			class := each instanceSide.
			((seen includes: class name) or: [ self hasRemoved: (self classNameFor: class) ]) ifFalse: [
				(class := self classFor: each) isNil ifFalse: [
					seen add: class name.
					aBlock
						value: class;
						value: class classSide ] ] ] ]
]

{ #category : #accessing }
RBNamespace >> allClassesDo: aBlock [
	| seen evalBlock |
	seen := Set new.
	evalBlock := [ :each | 
		seen add: each first name.
		aBlock
			value: each first;
			value: each last ].
	newClasses do: evalBlock.
	changedClasses do: evalBlock.
	environment classesDo: [ :each | 
		each isObsolete ifFalse: [
			| class |
			class := each instanceSide.
			((seen includes: class name) or: [ self hasRemoved: (self classNameFor: class) ]) ifFalse: [
				(class := self classFor: each) isNil ifFalse: [
					seen add: class name.
					aBlock value: class;
						    value: class classSide ] ] ] ]
]

{ #category : #accessing }
RBNamespace >> allImplementorsOf: aSelector [ 
	^ implementorsCache at: aSelector ifAbsentPut: [ self privateImplementorsOf: aSelector ]
]

{ #category : #accessing }
RBNamespace >> allImplementorsOf: aSelector do: aBlock [
	(self allImplementorsOf: aSelector) do: aBlock
]

{ #category : #accessing }
RBNamespace >> allReferencesTo: aSymbol [
	^ sendersCache at: aSymbol ifAbsentPut: [ self privateReferencesTo: aSymbol ]
]

{ #category : #accessing }
RBNamespace >> allReferencesTo: aSymbol do: aBlock [
	(self allReferencesTo: aSymbol) do: aBlock
]

{ #category : #accessing }
RBNamespace >> allReferencesToClass: aRBClass do: aBlock [ 
	self allClassesDo: 
			[:each |
			(each whichSelectorsReferToClass: aRBClass) 
				do: [:sel | aBlock value: (each methodFor: sel)].
			(each classSide whichSelectorsReferToClass: aRBClass) 
				do: [:sel | aBlock value: (each classSide methodFor: sel)]]
]

{ #category : #'private-changes' }
RBNamespace >> changeClass: aRBClass [ 
	changedClasses 
		at: aRBClass name
		put: (Array 
				with: aRBClass instanceSide
				with: aRBClass classSide).
	self flushCaches
]

{ #category : #accessing }
RBNamespace >> changes [
	^changes
]

{ #category : #'accessing-classes' }
RBNamespace >> classFor: aBehavior [ 
	aBehavior isNil 
		ifTrue: [ ^ nil ].
	^ aBehavior isMeta 
		ifTrue: [ self metaclassNamed: aBehavior instanceSide name ]
		ifFalse: [ self classNamed: aBehavior instanceSide name ]
]

{ #category : #private }
RBNamespace >> classNameFor: aBehavior [ 
	^ aBehavior instanceSide name
]

{ #category : #'accessing-classes' }
RBNamespace >> classNamed: aSymbol [ 
	| class classes index |
	aSymbol isNil ifTrue: [ ^ nil ].
	(self hasRemoved: aSymbol) ifTrue: [ ^ nil ].
	(newClasses includesKey: aSymbol) ifTrue: [ ^ (newClasses at: aSymbol) first ].
	(changedClasses includesKey: aSymbol) ifTrue: [ ^ (changedClasses at: aSymbol) first ].
	class := environment 
		at: aSymbol
		ifAbsent: [ nil ].
	(class isBehavior or: [ class isTrait ]) ifTrue: 
		[ classes := self createNewClassFor: class.
		^ class isMeta 
			ifTrue: [ classes last ]
			ifFalse: [ classes first ] ].
	index := aSymbol 
		indexOfSubCollection: ' class'
		startingAt: 1
		ifAbsent: [ ^ nil ].
	class := self classNamed: (aSymbol 
			copyFrom: 1
			to: index - 1) asSymbol.
	^ class isNil 
		ifTrue: [ nil ]
		ifFalse: [ class classSide ]
]

{ #category : #changes }
RBNamespace >> comment: aString in: aClass [
	^ changes comment: aString in: aClass
]

{ #category : #'private-changes' }
RBNamespace >> compile: aString in: aRBClass classified: aSymbol [ 
	| change |
	change := changes 
				compile: aString
				in: aRBClass
				classified: aSymbol.
	self flushCaches.
	^change
]

{ #category : #'accessing-classes' }
RBNamespace >> createNewClassFor: aBehavior [ 
	| nonMeta meta className |
	className := aBehavior instanceSide name.
	nonMeta := (RBClassModelFactory rbClass existingNamed: className)
				model: self;
				yourself.
	meta := (RBClassModelFactory rbMetaclass existingNamed: className)
				model: self;
				yourself.
	^changedClasses at: className put: (Array with: nonMeta with: meta)
]

{ #category : #changes }
RBNamespace >> defineClass: aString [
	| change newClass newClassName |
	change := changes defineClass: aString.
	newClassName := change changeClassName.
	newClass := self classNamed: newClassName.
	newClass isNil
		ifTrue: [ | newMetaclass |
			self unmarkAsRemoved: newClassName.
			newClass := RBClassModelFactory rbClass named: newClassName.
			newMetaclass := RBClassModelFactory rbMetaclass named: newClassName.
			newClass model: self.
			newMetaclass model: self.
			newClasses
				at: newClassName
				put: (Array with: newClass with: newMetaclass) ].
	newClass superclass: (self classNamed: change superclassName).
	newClass superclass isNil
		ifTrue: [ self rootClasses add: newClass.
			newClass classSide
				superclass: (self classFor: Object class superclass) ]
		ifFalse: [ newClass classSide superclass: newClass superclass classSide ].
	newClass instanceVariableNames: change instanceVariableNames.
	newClass classVariableNames: change classVariableNames.
	newClass poolDictionaryNames: change sharedPoolNames.
	newClass category: change category.
	^ change
]

{ #category : #accessing }
RBNamespace >> description [
	^ self changes name
]

{ #category : #accessing }
RBNamespace >> description: aString [
	self changes name: aString
]

{ #category : #accessing }
RBNamespace >> environment [
	^environment
]

{ #category : #accessing }
RBNamespace >> environment: aBrowserEnvironment [ 
	environment := aBrowserEnvironment
]

{ #category : #'private-changes' }
RBNamespace >> flushCaches [
	implementorsCache := IdentityDictionary new.
	sendersCache := IdentityDictionary new
]

{ #category : #private }
RBNamespace >> hasCreatedClassFor: aBehavior [ 
	| className |
	className := self classNameFor: aBehavior.
	^(newClasses includesKey: className) 
		or: [changedClasses includesKey: className]
]

{ #category : #testing }
RBNamespace >> hasRemoved: aSymbol [ 
	^removedClasses includes: aSymbol
]

{ #category : #testing }
RBNamespace >> includesClassNamed: aSymbol [ 
	^(self classNamed: aSymbol) notNil
]

{ #category : #testing }
RBNamespace >> includesGlobal: aSymbol [ 
	(self hasRemoved: aSymbol) ifTrue: [^false].
	(self includesClassNamed: aSymbol) ifTrue: [^true].
	environment at: aSymbol ifAbsent: [^false].
	^true
]

{ #category : #initialization }
RBNamespace >> initialize [
	changes := RBRefactoryChangeManager changeFactory compositeRefactoryChange.
	environment := RBBrowserEnvironment new.
	newClasses := IdentityDictionary new.
	changedClasses := IdentityDictionary new.
	removedClasses := Set new.
	implementorsCache := IdentityDictionary new.
	sendersCache := IdentityDictionary new
]

{ #category : #private }
RBNamespace >> markAsRemoved: aClassName [

	removedClasses
		add: aClassName;
		add: aClassName, ' class'
]

{ #category : #'accessing-classes' }
RBNamespace >> metaclassNamed: aSymbol [ 
	| class |
	aSymbol isNil ifTrue: [^nil].
	(self hasRemoved: aSymbol) ifTrue: [^nil].
	(newClasses includesKey: aSymbol) 
		ifTrue: [^(newClasses at: aSymbol) last].
	(changedClasses includesKey: aSymbol) 
		ifTrue: [^(changedClasses at: aSymbol) last].

	class := environment at: aSymbol ifAbsent: [nil].
	(class isBehavior or: [class isTrait])
		ifTrue: [^ (self createNewClassFor: class) last].
	^ nil
]

{ #category : #accessing }
RBNamespace >> name [
	^changes name
]

{ #category : #accessing }
RBNamespace >> name: aString [
	^changes name: aString
]

{ #category : #'private-changes' }
RBNamespace >> performChange: aCompositeRefactoryChange around: aBlock [ 
	| oldChanges |
	changes addChange: aCompositeRefactoryChange.
	oldChanges := changes.
	changes := aCompositeRefactoryChange.
	aBlock ensure: [changes := oldChanges].
	^aCompositeRefactoryChange
]

{ #category : #private }
RBNamespace >> privateImplementorsOf: aSelector [ 
	| classes |
	classes := Set new.
	self allClassesDo: [ :class |
		(class directlyDefinesLocalMethod: aSelector)
			ifTrue: [ classes add: class ].
		(class classSide directlyDefinesLocalMethod: aSelector)
			ifTrue: [ classes add: class classSide ] ].
	^ classes
]

{ #category : #private }
RBNamespace >> privateReferencesTo: aSelector [ 
	| methods |
	methods := OrderedCollection new.
	self allBehaviorsDo: [ :class |
		(class whichSelectorsReferToSymbol: aSelector)
			do: [ :selector |
				methods add: (class methodFor: selector) ] ].
	^ methods
]

{ #category : #private }
RBNamespace >> privateRootClasses [
	| classes |
	classes := OrderedCollection new.
	Class rootsOfTheWorld do: [ :each | 
		| class |
		class := self classFor: each.
		(class notNil and: [ class superclass isNil ]) 
			ifTrue: [ classes add: class ] ].
	^ classes
]

{ #category : #changes }
RBNamespace >> removeClass: aRBClass [ 
	self removeClassNamed: aRBClass name
]

{ #category : #changes }
RBNamespace >> removeClassNamed: aSymbol [ 
	(self classNamed: aSymbol) subclasses 
		do: [:each | self removeClassNamed: each name].
	removedClasses
		add: aSymbol;
		add: aSymbol , ' class'.
	newClasses removeKey: aSymbol ifAbsent: [].
	changedClasses removeKey: aSymbol ifAbsent: [].
	self flushCaches.
	^changes removeClassNamed: aSymbol
]

{ #category : #'private-changes' }
RBNamespace >> removeClassVariable: aString from: aRBClass [ 
	^changes removeClassVariable: aString from: aRBClass
]

{ #category : #'private-changes' }
RBNamespace >> removeInstanceVariable: aString from: aRBClass [ 
	^changes removeInstanceVariable: aString from: aRBClass
]

{ #category : #'private-changes' }
RBNamespace >> removeMethod: aSelector from: aRBClass [ 
	self flushCaches.
	^changes removeMethod: aSelector from: aRBClass
]

{ #category : #changes }
RBNamespace >> renameClass: aRBClass to: aSymbol around: aBlock [
	| change value dict |
	change := RBRefactoryChangeManager changeFactory renameClass: aRBClass to: aSymbol.
	self performChange: change around: aBlock.
	self flushCaches.
	dict := (newClasses includesKey: aRBClass name)
		ifTrue: [ newClasses ]
		ifFalse: [ changedClasses ].
	self markAsRemoved: aRBClass name.
	self unmarkAsRemoved: aSymbol.
	value := dict at: aRBClass name.
	dict removeKey: aRBClass name.
	dict at: aSymbol put: value.
	value first name: aSymbol.
	value last name: aSymbol.
	value first subclasses do: [ :each | each superclass: value first ].
	value last subclasses do: [ :each | each superclass: value last ].
	^ change
]

{ #category : #'private-changes' }
RBNamespace >> renameClassVariable: oldName to: newName in: aRBClass around: aBlock [ 
	^self performChange: (RBRefactoryChangeManager changeFactory  
				renameClassVariable: oldName
				to: newName
				in: aRBClass)
		around: aBlock
]

{ #category : #'private-changes' }
RBNamespace >> renameInstanceVariable: oldName to: newName in: aRBClass around: aBlock [ 
	^self performChange: (RBRefactoryChangeManager changeFactory 
				renameInstanceVariable: oldName
				to: newName
				in: aRBClass)
		around: aBlock
]

{ #category : #changes }
RBNamespace >> reparentClasses: aRBClassCollection to: newClass [ 
	aRBClassCollection do: 
			[:aClass | 
			self defineClass: (self replaceClassNameIn: aClass definitionString
						to: newClass name)]
]

{ #category : #'private-changes' }
RBNamespace >> replaceClassNameIn: definitionString to: aSymbol [ 
	| parseTree |
	parseTree := RBParser parseExpression: definitionString.
	parseTree receiver: (RBVariableNode named: aSymbol).
	^parseTree formattedCode
]

{ #category : #accessing }
RBNamespace >> rootClasses [
	^ rootClasses ifNil: [ rootClasses := self privateRootClasses]
]

{ #category : #private }
RBNamespace >> unmarkAsRemoved: newClassName [
	removedClasses
		remove: newClassName ifAbsent: [  ];
		remove: newClassName , ' class' ifAbsent: [  ]
]

{ #category : #'accessing-classes' }
RBNamespace >> whichCategoryIncludes: aSymbol [
	^self environment whichCategoryIncludes: aSymbol
]
