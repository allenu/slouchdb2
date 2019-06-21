//
//  Person.swift
//  PeopleApp
//
//  Created by Allen Ussher on 6/22/19.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import Foundation

struct Person {
    let identifier: String
    var name: String
    var weight: Int
    var age: Int
    
    static let namePropertyKey = "name"
    static let weightPropertyKey = "weight"
    static let agePropertyKey = "age"
}
