// Copied from https://review.opendev.org/c/zuul/zuul-operator/+/848103
// Copyright (C) 2022 Red Hat
// SPDX-License-Identifier: Apache-2.0

// Package v1 contains API Schema definitions for the Zuul API group
package zuul

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var (
	// GroupVersion is group version used to register these objects
	GroupVersion = schema.GroupVersion{Group: "operator.zuul-ci.org", Version: "v1alpha2"}

	// SchemeBuilder is used to add go types to the GroupVersionKind scheme
	SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}

	// AddToScheme adds the types in this group-version to the given scheme.
	AddToScheme = SchemeBuilder.AddToScheme
)
